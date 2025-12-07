# PostgreSQL 최적화

## 이력서 연결

> "PostgreSQL, TimescaleDB 기반 대용량 데이터 처리"
> "분당 50만 건 데이터 처리를 위한 Bulk Insert 최적화"
> "EXPLAIN ANALYZE 기반 쿼리 성능 튜닝"

---

## 핵심 답변 (STAR)

### Situation (상황)
- 한화솔루션 Telemetry, 50만대 장비의 실시간 데이터 수집
- 기존 단건 INSERT로는 처리량 한계
- 복잡한 조회 쿼리의 성능 문제

### Task (과제)
- 대용량 데이터 삽입 성능 최적화
- 쿼리 실행 계획 분석 및 튜닝
- 인덱스 전략 수립

### Action (행동)
1. **Bulk Insert 적용**
   - 단건 INSERT → Spring JDBC `batchUpdate`
   - 배치 크기 최적화 (500~1000건)

2. **EXPLAIN ANALYZE 분석**
   - Scan 타입 분석 (Seq, Index, Bitmap)
   - Join 알고리즘 이해 (Nested Loop, Hash, Merge)
   - Buffer 통계로 I/O 패턴 파악

3. **인덱스 최적화**
   - 복합 인덱스 설계
   - Covering Index로 Index Only Scan 유도
   - 선택도(Selectivity) 고려

### Result (결과)
- Bulk Insert로 삽입 성능 10배 이상 향상
- 쿼리 응답 시간 50ms → 5ms 개선
- DB 부하 감소, 안정적인 서비스 운영

---

## 예상 질문

### Q1: EXPLAIN과 EXPLAIN ANALYZE의 차이는?

**답변:**

```sql
-- 실행 계획만 보기 (실제 실행 안 함)
EXPLAIN SELECT * FROM users WHERE id = 1;

-- 실제 실행 + 실행 계획
EXPLAIN ANALYZE SELECT * FROM users WHERE id = 1;

-- 권장: 모든 정보 포함
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT) SELECT * FROM users WHERE id = 1;
```

| 구분 | EXPLAIN | EXPLAIN ANALYZE |
|------|---------|-----------------|
| 실행 여부 | ❌ 실행 안 함 | ✅ 실제 실행 |
| 예상 비용 | ✅ | ✅ |
| 실제 시간 | ❌ | ✅ |
| 실제 행 수 | ❌ | ✅ |
| Buffer 통계 | ❌ | ✅ (BUFFERS 옵션) |

**주의**: `EXPLAIN ANALYZE`는 실제 실행되므로 `INSERT`, `UPDATE`, `DELETE`는 트랜잭션으로 감싸야 한다.

### Q2: 실행 계획에서 뭘 봐야 하나요?

**답변:**
실행 계획의 주요 지표를 설명한다.

```
Seq Scan on users  (cost=0.00..458.00 rows=10000 width=244) (actual time=0.009..2.198 rows=10000 loops=1)
```

**cost (예상 비용)**:
- `0.00`: startup cost (첫 행 반환 전 비용)
- `458.00`: total cost (모든 행 반환까지 총 비용)

**rows**: 플래너가 예측한 반환 행 수
**width**: 평균 행 크기 (바이트)

**actual time, rows, loops**:
- `0.009`: 첫 행 반환까지 실제 시간 (ms)
- `2.198`: 모든 행 반환까지 실제 시간 (ms)
- `loops=1`: 이 노드 실행 횟수

**중요**: `loops > 1`이면 actual time은 **평균값**이다. 총 시간 = time × loops

### Q3: Scan 타입별 특성은?

**답변:**

| Scan Type | 언제 사용 | I/O 패턴 |
|-----------|----------|---------|
| **Seq Scan** | 대부분의 행 조회 | Sequential |
| **Index Scan** | 소수의 행 조회 | Random |
| **Bitmap Scan** | 중간 규모 조회 | Sequential (변환됨) |
| **Index Only Scan** | 인덱스만으로 충분 | Minimal |

**Seq Scan**:
- 테이블 전체를 순차적으로 읽음
- 대부분의 행을 읽을 때 효율적
- **Seq Scan이 항상 나쁜 건 아니다**

**Index Scan**:
- 인덱스로 위치 찾고 힙으로 이동
- 소수의 행에 효율적
- 많은 행이면 랜덤 I/O로 느려짐

**Bitmap Scan**:
- 인덱스 → 비트맵 → 페이지 순서로 정렬 → 순차 읽기
- 여러 인덱스 결합 가능 (BitmapAnd/BitmapOr)
- Index Scan과 Seq Scan의 중간

**Index Only Scan**:
- 힙 접근 없이 인덱스만으로 결과 반환
- 조건: SELECT 컬럼이 모두 인덱스에 포함
- `Heap Fetches`가 높으면 VACUUM 필요

### Q4: Join 알고리즘별 특성은?

**답변:**

| Algorithm | 복잡도 | Startup Cost | Best For |
|-----------|--------|--------------|----------|
| **Nested Loop** | O(n×m) | 낮음 | 작은 테이블, 인덱스 있음 |
| **Hash Join** | O(n+m) | 높음 | 큰 테이블, Equi-join |
| **Merge Join** | O(n log n) | 중간 | 정렬된 데이터, Range join |

**Nested Loop Join**:
```
외부 테이블의 각 행에 대해 내부 테이블 스캔
```
- 한쪽 테이블이 매우 작을 때
- 내부 테이블에 인덱스 있을 때
- LIMIT이 있을 때 유리 (첫 결과 빠름)

**Hash Join**:
```
작은 테이블 → 해시 테이블 빌드 → 큰 테이블 스캔하며 조회
```
- 두 테이블 모두 클 때
- Equi-join(=)만 가능
- `work_mem` 부족 시 디스크 사용

**Merge Join**:
```
양쪽 정렬 → 순차적으로 병합
```
- 데이터가 이미 정렬되어 있을 때
- Range join (>=, <=)에 적합

### Q5: Bulk Insert는 어떻게 구현했나요?

**답변:**
Spring JDBC의 `batchUpdate`를 사용했다.

```kotlin
@Repository
class TelemetryJdbcRepository(
    private val jdbcTemplate: JdbcTemplate
) {
    fun bulkInsert(records: List<TelemetryRecord>) {
        val sql = """
            INSERT INTO telemetry (device_id, timestamp, value, metadata)
            VALUES (?, ?, ?, ?::jsonb)
        """.trimIndent()

        jdbcTemplate.batchUpdate(sql, records, 1000) { ps, record ->
            ps.setString(1, record.deviceId)
            ps.setTimestamp(2, Timestamp.valueOf(record.timestamp))
            ps.setDouble(3, record.value)
            ps.setString(4, record.metadata.toJson())
        }
    }
}
```

**성능 포인트**:
- 배치 크기 1000건: 너무 작으면 라운드트립 증가, 너무 크면 메모리 부담
- `reWriteBatchedInserts=true`: JDBC URL에 설정하면 Multi-row INSERT로 변환
- Prepared Statement 재사용: 파싱 비용 절감

**결과**:
| 방식 | 1만 건 처리 시간 |
|------|-----------------|
| 단건 INSERT | ~10초 |
| Batch Update | ~1초 |
| Multi-row INSERT | ~0.5초 |

---

## 꼬리 질문 대비

### Q: 인덱스는 어떻게 설계했나요?

**답변:**
세 가지 원칙을 따랐다.

**1. 선택도(Selectivity) 고려**
```sql
-- 선택도가 높은 컬럼 (값이 고유할수록 좋음)
CREATE INDEX idx_users_email ON users(email);  -- 좋음

-- 선택도가 낮은 컬럼 (값이 적을수록 나쁨)
CREATE INDEX idx_users_gender ON users(gender);  -- 나쁨
```

**2. 복합 인덱스 컬럼 순서**
```sql
-- WHERE에 자주 쓰이는 컬럼을 앞에
-- 선택도가 높은 컬럼을 앞에
CREATE INDEX idx_orders ON orders(user_id, created_at);

-- 쿼리: WHERE user_id = ? AND created_at > ?
-- → 인덱스 효율적 사용
```

**3. Covering Index로 Index Only Scan 유도**
```sql
-- SELECT 절의 컬럼까지 인덱스에 포함
CREATE INDEX idx_users_email_name ON users(email, name);

-- 쿼리: SELECT email, name FROM users WHERE email = ?
-- → Index Only Scan (힙 접근 없음)
```

### Q: 예상 행 수와 실제 행 수가 다르면?

**답변:**
플래너의 추정이 잘못되면 비효율적인 실행 계획이 선택된다.

```
Seq Scan on users  (cost=... rows=100) (actual ... rows=10000)
```

**원인과 해결**:

| 원인 | 해결 |
|------|------|
| 통계 오래됨 | `ANALYZE users;` |
| 상관관계 컬럼 | Extended Statistics 생성 |
| 함수/표현식 | 통계 수집 불가 (인덱스 고려) |

**Extended Statistics 예시**:
```sql
-- city와 country는 상관관계가 있음
CREATE STATISTICS city_country_stats (dependencies)
ON city, country FROM addresses;
ANALYZE addresses;
```

### Q: Buffer 통계는 어떻게 해석하나요?

**답변:**

```
Buffers: shared hit=10000 read=500
```

- **hit**: shared_buffers 캐시에서 읽음 (빠름)
- **read**: 디스크 또는 OS 캐시에서 읽음 (느림)

**캐시 히트율**: 10000 / 10500 = 95.2%

**read가 높으면?**
- 첫 실행이라 warm-up 필요
- `shared_buffers` 부족
- 데이터셋이 메모리보다 큼

### Q: 병렬 쿼리는 어떻게 활용하나요?

**답변:**

```
Gather  (cost=... rows=100000 width=244)
  Workers Planned: 4
  Workers Launched: 4
  ->  Parallel Seq Scan on large_table
```

**관련 설정**:
```sql
-- 쿼리당 최대 워커 수
SET max_parallel_workers_per_gather = 4;

-- 병렬 쿼리 시작 임계값
SET min_parallel_table_scan_size = '8MB';
```

`Workers Launched < Workers Planned`면 워커 부족이다.

### Q: SSD 환경에서 튜닝 포인트는?

**답변:**
`random_page_cost`를 낮춰야 한다.

```sql
-- HDD 기본값
random_page_cost = 4.0  -- Sequential의 4배 비용

-- SSD에서 권장
SET random_page_cost = 1.1;  -- Random I/O가 저렴
```

이 값이 높으면 플래너가 Seq Scan을 선호한다. SSD에서는 Index Scan이 더 유리한 경우가 많다.

---

## 관련 개념 정리

| 개념 | 설명 |
|------|------|
| EXPLAIN ANALYZE | 실제 실행하며 실행 계획 분석 |
| Seq Scan | 테이블 전체 순차 스캔 |
| Index Scan | 인덱스로 위치 찾고 힙 접근 |
| Bitmap Scan | 비트맵으로 랜덤 I/O를 순차로 변환 |
| Index Only Scan | 힙 접근 없이 인덱스만으로 결과 |
| Nested Loop | 외부 테이블의 각 행마다 내부 스캔 |
| Hash Join | 해시 테이블 빌드 후 조회 |
| Merge Join | 정렬 후 병합 |
| work_mem | 정렬/해시에 사용되는 메모리 |
| shared_buffers | PostgreSQL 캐시 메모리 |

---

## 최적화 체크리스트

### 1. 예상 vs 실제 행 수
```
rows=100 (예상) vs rows=10000 (실제)
```
10배 이상 차이나면 `ANALYZE` 실행.

### 2. 의도치 않은 Seq Scan
인덱스가 있는데 Seq Scan이면:
- `random_page_cost`가 너무 높음
- 통계가 오래됨
- 실제로 Seq Scan이 최적 (대부분의 행 조회)

### 3. Nested Loop의 loops가 높음
```
->  Index Scan  (actual ... loops=100000)
```
Hash Join으로 바꾸는 게 나을 수 있다.

### 4. 디스크 정렬 발생
```
Sort Method: external merge  Disk: 102400kB
```
`work_mem`을 늘려서 메모리 정렬로 전환.

### 5. Heap Fetches가 높음
```
Index Only Scan  ...  Heap Fetches: 8500
```
`VACUUM`을 실행해서 Visibility Map 갱신.

---

## 아키텍처 다이어그램

```
┌─────────────────┐
│     Query       │
└────────┬────────┘
         ▼
┌─────────────────┐
│     Parser      │  → 구문 분석
└────────┬────────┘
         ▼
┌─────────────────┐
│    Planner      │  → 실행 계획 생성
│  (EXPLAIN 출력) │     pg_statistic 참조
└────────┬────────┘
         ▼
┌─────────────────┐
│    Executor     │  → 실행 계획 실행
│ (ANALYZE 출력)  │
└────────┬────────┘
         ▼
┌─────────────────┐
│ shared_buffers  │ ← 캐시
└────────┬────────┘
         │ Miss
         ▼
┌─────────────────┐
│   OS Page Cache │
└────────┬────────┘
         │ Miss
         ▼
┌─────────────────┐
│      Disk       │
└─────────────────┘
```

---

## 기술 선택과 Trade-off

### 왜 PostgreSQL을 선택했는가?

**대안 비교:**

| DB | JSONB | 시계열 | 트랜잭션 | 확장성 |
|----|-------|--------|----------|--------|
| **PostgreSQL** | 우수 | TimescaleDB | ACID | 수직/수평 |
| **MySQL** | 제한적 | 없음 | ACID | 수직 |
| **MongoDB** | 네이티브 | 제한적 | 제한적 | 수평 |
| **InfluxDB** | X | 최적화 | X | 수평 |

**PostgreSQL 선택 이유:**
- JSONB로 유연한 텔레메트리 데이터 저장
- TimescaleDB 확장으로 시계열 데이터 처리
- 강력한 트랜잭션 보장
- 팀의 기존 경험 활용

### Bulk Insert 방식 Trade-off

| 방식 | 성능 | 구현 복잡도 | 메모리 | 에러 핸들링 |
|------|------|-------------|--------|-------------|
| **단건 INSERT** | 느림 | 쉬움 | 낮음 | 쉬움 |
| **JDBC Batch** | 빠름 | 중간 | 중간 | 배치 단위 |
| **Multi-row INSERT** | 매우 빠름 | 중간 | 높음 | 배치 단위 |
| **COPY** | 가장 빠름 | 높음 | 낮음 | 전체 실패 |

**JDBC Batch + reWriteBatchedInserts 선택 이유:**
- COPY: 에러 시 전체 롤백, 유연성 부족
- Multi-row: SQL 문자열 크기 제한
- **JDBC Batch가 성능과 에러 핸들링의 균형점**

### 인덱스 설계 Trade-off

| 인덱스 타입 | 쓰기 성능 | 저장 공간 | 조회 성능 |
|------------|----------|----------|----------|
| **없음** | 빠름 | 없음 | Seq Scan |
| **B-tree** | 중간 | 중간 | 좋음 |
| **Covering** | 느림 | 큼 | 매우 좋음 |
| **Partial** | 빠름 | 작음 | 조건부 좋음 |

**설계 원칙:**
- 읽기 빈번: Covering Index 고려
- 쓰기 빈번: 최소 인덱스
- 특정 조건만: Partial Index

### 복합 인덱스 컬럼 순서

```sql
-- 쿼리: WHERE tenant_id = ? AND created_at > ?
CREATE INDEX idx_1 ON table(tenant_id, created_at);  -- ✓ 좋음
CREATE INDEX idx_2 ON table(created_at, tenant_id);  -- ✗ 나쁨
```

**순서 결정 기준:**
1. 등호(=) 조건 컬럼 먼저
2. 범위(<, >) 조건 컬럼 나중
3. 선택도 높은 컬럼 먼저

### SSD 환경 튜닝 Trade-off

| 설정 | HDD 기본값 | SSD 권장값 | 효과 |
|------|-----------|-----------|------|
| **random_page_cost** | 4.0 | 1.1 | Index Scan 선호 |
| **effective_io_concurrency** | 1 | 200 | 병렬 I/O |

**튜닝 이유:**
- HDD: Random I/O가 Sequential보다 4배 비용
- SSD: Random/Sequential 비용 차이 거의 없음
- 기본값 사용 시 불필요한 Seq Scan 발생

### work_mem 설정 Trade-off

```
낮음 (4MB): 디스크 정렬 빈번 → 느림
높음 (1GB): 메모리 부족 위험 (동시 쿼리 × work_mem)
적절함 (64-256MB): 균형점
```

**설정 전략:**
- 전역: 보수적으로 설정
- 세션/쿼리별: 필요 시 상향
- 모니터링: `Sort Method: external merge` 발생 시 상향 고려

---

## 블로그 링크

- [PostgreSQL EXPLAIN ANALYZE 가이드](https://gyeom.github.io/dev-notes/posts/2025-07-10-postgresql-explain-analyze-complete-guide/)
- [Kafka 대용량 메시지 처리 (Bulk Insert 포함)](https://gyeom.github.io/dev-notes/posts/2023-12-08-kafka-high-volume-processing/)

---

*다음: [11-timescaledb.md](./11-timescaledb.md)*
