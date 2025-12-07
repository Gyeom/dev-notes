# 데이터베이스 (PostgreSQL, Redis, TimescaleDB)

## MVCC (Multi-Version Concurrency Control)

### 개념

동시성 제어 방식. 읽기와 쓰기가 서로를 블로킹하지 않는다.

```
Transaction 1: SELECT * FROM orders WHERE id = 1;
                  ↓ (스냅샷 읽기)
Transaction 2: UPDATE orders SET status = 'completed' WHERE id = 1;
                  ↓ (새 버전 생성)
Transaction 1: 여전히 이전 버전을 본다 (일관된 읽기)
```

### PostgreSQL의 MVCC 구현

| 구성요소 | 설명 |
|----------|------|
| `xmin` | 해당 행을 생성한 트랜잭션 ID |
| `xmax` | 해당 행을 삭제/수정한 트랜잭션 ID (0이면 유효) |
| Snapshot | 트랜잭션 시작 시점의 활성 트랜잭션 목록 |

```sql
-- 내부 시스템 컬럼 조회
SELECT xmin, xmax, * FROM orders WHERE id = 1;
```

### 가시성 판단

```
행이 보이려면:
1. xmin이 커밋되었고
2. xmax가 없거나 (아직 살아있거나)
3. xmax가 커밋되지 않았거나
4. xmax가 현재 트랜잭션 이후에 커밋됨
```

### MVCC의 장단점

| 장점 | 단점 |
|------|------|
| 읽기-쓰기 충돌 없음 | Dead Tuple 누적 |
| 락 오버헤드 감소 | 저장 공간 증가 |
| 일관된 읽기 보장 | VACUUM 필요 |

---

## VACUUM

### Dead Tuple

UPDATE/DELETE 시 이전 버전이 즉시 삭제되지 않는다.

```
UPDATE orders SET status = 'completed';

Before: [id=1, status='pending', xmax=0]  ← Live
After:  [id=1, status='pending', xmax=100] ← Dead (이전 버전)
        [id=1, status='completed', xmin=100] ← Live (새 버전)
```

### VACUUM 종류

| 종류 | 동작 | 락 |
|------|------|-----|
| **VACUUM** | Dead Tuple 공간 재사용 가능 표시 | 읽기/쓰기 허용 |
| **VACUUM FULL** | 테이블 재작성, 공간 반환 | 배타적 락 (서비스 중단) |
| **VACUUM ANALYZE** | VACUUM + 통계 갱신 | 읽기/쓰기 허용 |

### Autovacuum

```sql
-- 현재 설정 확인
SHOW autovacuum_vacuum_threshold;      -- 기본 50
SHOW autovacuum_vacuum_scale_factor;   -- 기본 0.2

-- 트리거 조건: dead tuples > threshold + (scale_factor × table rows)
-- 예: 1000행 테이블 → 50 + 0.2×1000 = 250개 dead tuple 시 실행
```

### 테이블별 설정

```sql
ALTER TABLE high_churn_table SET (
    autovacuum_vacuum_scale_factor = 0.05,  -- 5%마다
    autovacuum_vacuum_threshold = 100
);
```

### VACUUM 모니터링

```sql
-- Dead Tuple 확인
SELECT relname, n_dead_tup, n_live_tup,
       round(n_dead_tup::numeric / nullif(n_live_tup, 0) * 100, 2) as dead_ratio
FROM pg_stat_user_tables
ORDER BY n_dead_tup DESC;

-- 마지막 VACUUM 시간
SELECT relname, last_vacuum, last_autovacuum
FROM pg_stat_user_tables;
```

---

## Transaction Isolation Level

### 4가지 레벨

| Level | Dirty Read | Non-Repeatable Read | Phantom Read |
|-------|------------|---------------------|--------------|
| READ UNCOMMITTED | ⚠️ 가능* | ⚠️ 가능 | ⚠️ 가능 |
| READ COMMITTED | ❌ 방지 | ⚠️ 가능 | ⚠️ 가능 |
| REPEATABLE READ | ❌ 방지 | ❌ 방지 | ⚠️ 가능* |
| SERIALIZABLE | ❌ 방지 | ❌ 방지 | ❌ 방지 |

*PostgreSQL에서는 READ UNCOMMITTED = READ COMMITTED, REPEATABLE READ에서 Phantom Read도 방지

### 현상 설명

```sql
-- Dirty Read: 커밋되지 않은 데이터 읽기
-- T1: UPDATE orders SET amount = 200;  (커밋 전)
-- T2: SELECT amount FROM orders;  → 200 (더티)
-- T1: ROLLBACK;
-- T2: 200을 기반으로 잘못된 계산

-- Non-Repeatable Read: 같은 쿼리가 다른 결과
-- T1: SELECT amount FROM orders WHERE id = 1;  → 100
-- T2: UPDATE orders SET amount = 200 WHERE id = 1; COMMIT;
-- T1: SELECT amount FROM orders WHERE id = 1;  → 200 (다름!)

-- Phantom Read: 새로운 행이 나타남
-- T1: SELECT COUNT(*) FROM orders WHERE date = today;  → 10
-- T2: INSERT INTO orders (date) VALUES (today); COMMIT;
-- T1: SELECT COUNT(*) FROM orders WHERE date = today;  → 11 (팬텀!)
```

### PostgreSQL 설정

```sql
-- 세션 레벨
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;

-- 트랜잭션 레벨
BEGIN TRANSACTION ISOLATION LEVEL SERIALIZABLE;
```

### 실무 선택 가이드

| 상황 | 권장 레벨 | 이유 |
|------|----------|------|
| 일반 CRUD | READ COMMITTED | 기본값, 충분한 일관성 |
| 재고 차감, 잔액 변경 | REPEATABLE READ | 동일 트랜잭션 내 일관성 필요 |
| 금융 정산, 감사 로그 | SERIALIZABLE | 완벽한 직렬화 필요 |

---

## N+1 Problem

### 문제 상황

```kotlin
// 주문 10건 조회 시
val orders = orderRepository.findAll()  // 1번 쿼리

orders.forEach { order ->
    println(order.user.name)  // 10번 쿼리 (각 주문마다 User 조회)
}
// 총 11번 쿼리 = 1 + N
```

### 해결책 1: Fetch Join

```kotlin
@Query("SELECT o FROM Order o JOIN FETCH o.user")
fun findAllWithUser(): List<Order>

// 1번 쿼리로 해결
```

**주의**: 컬렉션 Fetch Join은 페이징 불가

```kotlin
// ❌ 메모리에서 페이징 (위험)
@Query("SELECT o FROM Order o JOIN FETCH o.items")
fun findAllWithItems(pageable: Pageable): Page<Order>
```

### 해결책 2: @EntityGraph

```kotlin
@EntityGraph(attributePaths = ["user", "items"])
fun findAll(): List<Order>
```

### 해결책 3: @BatchSize

```kotlin
@Entity
class Order {
    @BatchSize(size = 100)
    @OneToMany(mappedBy = "order")
    val items: List<OrderItem> = emptyList()
}

// IN 쿼리로 일괄 조회
// SELECT * FROM items WHERE order_id IN (1, 2, 3, ..., 100)
```

### 해결책 4: Subselect

```kotlin
@Fetch(FetchMode.SUBSELECT)
@OneToMany(mappedBy = "order")
val items: List<OrderItem> = emptyList()

// 서브쿼리로 조회
// SELECT * FROM items WHERE order_id IN (SELECT id FROM orders WHERE ...)
```

### 비교

| 방식 | 쿼리 수 | 페이징 | 복잡도 |
|------|---------|--------|--------|
| Fetch Join | 1 | ❌ (컬렉션) | 중간 |
| EntityGraph | 1 | ❌ (컬렉션) | 낮음 |
| @BatchSize | 1 + N/batch | ✅ | 낮음 |
| Subselect | 2 | ✅ | 낮음 |

---

## 락 (Lock)

### 락 종류

| 락 | 설명 | 호환성 |
|---|------|--------|
| **Shared (S)** | 읽기 락 | S끼리 호환 |
| **Exclusive (X)** | 쓰기 락 | 모두 배타적 |
| **Row Share** | SELECT FOR UPDATE | |
| **Row Exclusive** | UPDATE, DELETE | |

### SELECT FOR UPDATE

```sql
-- 비관적 락: 다른 트랜잭션의 수정 차단
BEGIN;
SELECT * FROM orders WHERE id = 1 FOR UPDATE;
-- 이 시점에서 다른 트랜잭션은 대기
UPDATE orders SET status = 'completed' WHERE id = 1;
COMMIT;
```

### NOWAIT / SKIP LOCKED

```sql
-- 락을 못 얻으면 즉시 에러
SELECT * FROM orders WHERE id = 1 FOR UPDATE NOWAIT;

-- 락 걸린 행은 건너뛰기 (작업 큐 패턴)
SELECT * FROM job_queue WHERE status = 'pending'
FOR UPDATE SKIP LOCKED LIMIT 1;
```

### Deadlock

```
T1: X-lock on A, 대기 for B
T2: X-lock on B, 대기 for A
→ Deadlock!
```

**방지 방법:**
- 항상 같은 순서로 락 획득
- 타임아웃 설정
- 락 범위 최소화

```sql
-- 타임아웃 설정
SET lock_timeout = '5s';
```

---

## 인덱스 심화

### B-Tree vs Hash vs GIN vs GiST

| 인덱스 | 용도 | 지원 연산 |
|--------|------|----------|
| **B-Tree** | 기본, 범위 쿼리 | =, <, >, BETWEEN, LIKE 'abc%' |
| **Hash** | 동등 비교만 | = |
| **GIN** | 전문 검색, 배열, JSONB | @>, ?, ?& |
| **GiST** | 지리, 범위 타입 | &&, @>, <@ |

### Partial Index

조건에 맞는 행만 인덱싱:

```sql
-- active 주문만 인덱싱 (훨씬 작은 인덱스)
CREATE INDEX idx_active_orders ON orders(created_at)
WHERE status = 'active';

-- 쿼리도 같은 조건 필요
SELECT * FROM orders WHERE status = 'active' AND created_at > now() - interval '1 day';
```

### Expression Index

```sql
-- 함수 결과 인덱싱
CREATE INDEX idx_users_lower_email ON users(lower(email));

-- 쿼리
SELECT * FROM users WHERE lower(email) = 'test@example.com';
```

### INCLUDE (Covering Index in PostgreSQL 11+)

```sql
-- 인덱스에 추가 컬럼 포함 (검색에는 사용 안 함)
CREATE INDEX idx_orders_user ON orders(user_id) INCLUDE (status, total);

-- Index Only Scan 가능
SELECT status, total FROM orders WHERE user_id = 123;
```

---

## Connection Pool

### HikariCP 설정

```yaml
spring:
  datasource:
    hikari:
      maximum-pool-size: 10
      minimum-idle: 5
      connection-timeout: 30000
      idle-timeout: 600000
      max-lifetime: 1800000
```

### 적정 Pool 크기

```
connections = (core_count * 2) + effective_spindle_count
```

- core_count: CPU 코어 수
- effective_spindle_count: SSD면 1, HDD면 디스크 수

**일반적 권장**: 10-20개 (대부분의 애플리케이션에 충분)

### Connection Leak 감지

```yaml
spring:
  datasource:
    hikari:
      leak-detection-threshold: 60000  # 60초 이상 반환 안 하면 경고
```

---

## PostgreSQL EXPLAIN ANALYZE

### 기본 사용법

```sql
-- 실행 계획만 (실제 실행 안 함)
EXPLAIN SELECT * FROM users WHERE id = 1;

-- 실제 실행 + 통계
EXPLAIN ANALYZE SELECT * FROM users WHERE id = 1;

-- 권장: 모든 정보 포함
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT) SELECT * FROM users;
```

### 실행 계획 읽기

```
Seq Scan on users  (cost=0.00..458.00 rows=10000 width=244) (actual time=0.009..2.198 rows=10000 loops=1)
```

| 항목 | 의미 |
|------|------|
| `cost=0.00..458.00` | startup cost..total cost |
| `rows=10000` | 예상 반환 행 수 |
| `width=244` | 평균 행 크기 (바이트) |
| `actual time` | 실제 실행 시간 (ms) |
| `loops=1` | 실행 횟수 |

**주의**: loops > 1이면 actual time은 평균. 총 시간 = time × loops

---

## Scan Types

| Scan Type | 언제 사용 | I/O 패턴 |
|-----------|----------|---------|
| **Seq Scan** | 대부분의 행 조회 | Sequential |
| **Index Scan** | 소수의 행 조회 | Random |
| **Bitmap Scan** | 중간 규모 조회 | Sequential (변환) |
| **Index Only Scan** | 인덱스만으로 충분 | Minimal |

### Seq Scan

테이블 전체를 순차적으로 읽음.

```sql
-- 대부분의 행을 읽을 때 효율적
SELECT * FROM users WHERE status = 'active';  -- 80%가 active면 Seq Scan
```

**Seq Scan이 항상 나쁜 건 아니다.**

### Index Scan

인덱스로 위치 찾고 힙(테이블)으로 이동.

```sql
-- 소수의 행 조회 시
SELECT * FROM users WHERE id = 123;
```

### Bitmap Scan

여러 인덱스 결합 가능, 랜덤 I/O를 순차로 변환.

```sql
-- BitmapAnd: 여러 조건 결합
SELECT * FROM users WHERE age > 30 AND city = 'Seoul';
```

### Index Only Scan

힙 접근 없이 인덱스만으로 결과 반환.

```sql
-- 조건: SELECT 컬럼이 모두 인덱스에 포함
CREATE INDEX idx_users_email_name ON users(email, name);
SELECT email, name FROM users WHERE email = 'a@b.com';  -- Index Only Scan
```

`Heap Fetches`가 높으면 VACUUM 필요.

---

## Join Algorithms

| Algorithm | 복잡도 | Best For |
|-----------|--------|----------|
| **Nested Loop** | O(n×m) | 작은 테이블, 인덱스 |
| **Hash Join** | O(n+m) | 큰 테이블, Equi-join |
| **Merge Join** | O(n log n) | 정렬된 데이터 |

### Nested Loop

```
외부 테이블의 각 행에 대해 내부 테이블 스캔
```

- 한쪽이 매우 작을 때
- 내부 테이블에 인덱스 있을 때
- LIMIT 있을 때 유리

### Hash Join

```
작은 테이블 → 해시 테이블 빌드 → 큰 테이블 스캔하며 조회
```

- 두 테이블 모두 클 때
- Equi-join(=)만 가능
- `work_mem` 부족 시 디스크 사용

### Merge Join

```
양쪽 정렬 → 순차적으로 병합
```

- 데이터가 이미 정렬되어 있을 때
- Range join (>=, <=)에 적합

---

## 인덱스 설계

### 선택도 (Selectivity)

```sql
-- 높은 선택도 (좋음) - 값이 고유할수록
CREATE INDEX idx_email ON users(email);

-- 낮은 선택도 (나쁨) - 값이 적을수록
CREATE INDEX idx_gender ON users(gender);  -- M/F만 있으면 비효율
```

### 복합 인덱스 순서

```sql
-- 쿼리: WHERE tenant_id = ? AND created_at > ?

-- 좋음: 등호 조건 먼저
CREATE INDEX idx_1 ON orders(tenant_id, created_at);

-- 나쁨: 범위 조건 먼저
CREATE INDEX idx_2 ON orders(created_at, tenant_id);
```

**순서 결정 기준:**
1. 등호(=) 조건 컬럼 먼저
2. 범위(<, >) 조건 컬럼 나중
3. 선택도 높은 컬럼 먼저

### Covering Index

```sql
-- Index Only Scan 유도
CREATE INDEX idx_covering ON users(email, name, created_at);

SELECT email, name FROM users WHERE email = 'a@b.com';
-- 힙 접근 없이 인덱스만으로 결과
```

---

## Bulk Insert

### 방식 비교

| 방식 | 성능 | 구현 | 에러 핸들링 |
|------|------|------|-------------|
| 단건 INSERT | 느림 | 쉬움 | 개별 |
| JDBC Batch | 빠름 | 중간 | 배치 단위 |
| Multi-row | 매우 빠름 | 중간 | 배치 단위 |
| COPY | 가장 빠름 | 높음 | 전체 실패 |

### JDBC Batch

```kotlin
jdbcTemplate.batchUpdate(
    "INSERT INTO telemetry (device_id, value) VALUES (?, ?)",
    records,
    1000  // 배치 크기
) { ps, record ->
    ps.setString(1, record.deviceId)
    ps.setDouble(2, record.value)
}
```

### reWriteBatchedInserts

```
jdbc:postgresql://host:5432/db?reWriteBatchedInserts=true
```

여러 INSERT를 단일 Multi-row INSERT로 변환.

---

## TimescaleDB

### Hypertable

시계열 데이터를 위한 자동 파티셔닝 테이블.

```sql
CREATE TABLE telemetry (
    time        TIMESTAMPTZ NOT NULL,
    device_id   TEXT NOT NULL,
    value       DOUBLE PRECISION
);

SELECT create_hypertable('telemetry', 'time');
```

### Chunk

시간 기반 자동 파티션.

```sql
-- 기본: 7일 간격
-- 변경:
SELECT set_chunk_time_interval('telemetry', INTERVAL '1 day');
```

### Continuous Aggregates

실시간 집계 뷰.

```sql
CREATE MATERIALIZED VIEW hourly_avg
WITH (timescaledb.continuous) AS
SELECT
    time_bucket('1 hour', time) AS bucket,
    device_id,
    AVG(value) AS avg_value
FROM telemetry
GROUP BY bucket, device_id;

-- 자동 갱신 정책
SELECT add_continuous_aggregate_policy('hourly_avg',
    start_offset => INTERVAL '3 hours',
    end_offset => INTERVAL '1 hour',
    schedule_interval => INTERVAL '1 hour'
);
```

### Compression

```sql
ALTER TABLE telemetry SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'device_id'
);

SELECT add_compression_policy('telemetry', INTERVAL '7 days');
```

---

## Redis 캐싱

### Cache-Aside 패턴

```kotlin
fun getUser(id: String): User {
    // 1. 캐시 조회
    redis.get("user:$id")?.let { return it }

    // 2. DB 조회
    val user = userRepository.findById(id)

    // 3. 캐시 저장
    redis.set("user:$id", user, Duration.ofMinutes(30))

    return user
}
```

### 캐시 패턴 비교

| 패턴 | 동작 | 장점 | 단점 |
|------|------|------|------|
| **Cache-Aside** | 읽기: 캐시 → DB | 단순, 선택적 캐싱 | 첫 요청 느림 |
| **Write-Through** | 쓰기: 캐시+DB 동시 | 일관성 보장 | 쓰기 지연 |
| **Write-Behind** | 쓰기: 캐시만 → 비동기 DB | 쓰기 빠름 | 유실 위험 |

### Cache Stampede

캐시 만료 시 다수 요청이 동시에 DB로 몰리는 현상.

**해결: 분산 락 + Double-check**

```kotlin
fun getUser(id: String): User {
    redis.get(key)?.let { return it }

    val lock = lockRegistry.obtain(key)
    if (lock.tryLock(100, TimeUnit.MILLISECONDS)) {
        try {
            redis.get(key)?.let { return it }  // Double-check
            val user = userRepository.findById(id)
            redis.set(key, user)
            return user
        } finally {
            lock.unlock()
        }
    } else {
        Thread.sleep(50)
        return getUser(id)  // 재시도
    }
}
```

### TTL 전략

| 데이터 유형 | TTL | 무효화 |
|------------|-----|--------|
| 자주 변경 | 1-5분 | 이벤트 기반 |
| 가끔 변경 | 30분-1시간 | TTL + 이벤트 |
| 거의 고정 | 24시간+ | TTL만 |

### 직렬화

| 방식 | 크기 | 가독성 | 호환성 |
|------|------|--------|--------|
| JDK | 큼 | X | 낮음 |
| JSON | 중간 | O | 높음 |
| Protobuf | 작음 | X | 높음 |

**JSON 권장**: 디버깅 용이, 클래스 변경에 유연.

---

## 관련 Interview 문서

- [09-redis-caching.md](../interview/09-redis-caching.md)
- [10-postgresql.md](../interview/10-postgresql.md)
- [11-timescaledb.md](../interview/11-timescaledb.md)

---

*다음: [05-architecture.md](./05-architecture.md)*
