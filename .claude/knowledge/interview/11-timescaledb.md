# TimescaleDB 시계열 데이터

## 이력서 연결

> "PostgreSQL, TimescaleDB 기반 대용량 데이터 처리"
> "50만대 장비의 Telemetry 데이터 수집 파이프라인 설계"

---

## 핵심 답변 (STAR)

### Situation (상황)
- 한화솔루션 HEMS, 50만대 장비의 실시간 텔레메트리 데이터
- 초당 수만 건의 시계열 데이터 저장 및 조회
- 시간 범위 쿼리, 집계 분석 요구사항

### Task (과제)
- 대용량 시계열 데이터 저장소 선택
- 시간 기반 쿼리 최적화
- 장기 데이터 관리 전략

### Action (행동)
1. **TimescaleDB 도입 검토**
   - PostgreSQL 호환성 (기존 생태계 활용)
   - Hypertable 기반 자동 파티셔닝
   - Continuous Aggregates로 실시간 집계

2. **아키텍처 설계**
   - Hot (최근 데이터) / Warm (압축) / Cold (아카이브) 계층화
   - 적절한 chunk 크기 설정
   - 압축 정책 적용

3. **쿼리 최적화**
   - time_bucket 함수 활용
   - Continuous Aggregates로 집계 캐싱
   - 인덱스 전략 수립

### Result (결과)
- 분당 50만 건 데이터 안정적 처리
- 집계 쿼리 응답 시간 대폭 개선
- PostgreSQL 도구/라이브러리 그대로 사용

---

## 예상 질문

### Q1: TimescaleDB를 선택한 이유는?

**답변:**
세 가지 이유로 TimescaleDB를 선택했다.

**1. PostgreSQL 완전 호환**
```sql
-- 기존 PostgreSQL 쿼리 그대로 사용
SELECT * FROM telemetry
WHERE device_id = 'dev-123'
  AND timestamp > NOW() - INTERVAL '1 hour';

-- JPA, QueryDSL 그대로 사용 가능
```

**2. 자동 파티셔닝 (Hypertable)**
```sql
-- 일반 테이블을 Hypertable로 변환
SELECT create_hypertable('telemetry', 'timestamp');

-- 자동으로 시간 기반 청크 생성
-- 별도의 파티션 관리 불필요
```

**3. 시계열 최적화 기능**
- `time_bucket()`: 시간 구간별 집계
- Continuous Aggregates: 실시간 집계 뷰
- 압축: 저장 공간 90% 절약

**다른 DB와 비교:**

| 기준 | TimescaleDB | MongoDB | ClickHouse |
|------|-------------|---------|------------|
| SQL 지원 | ✅ 완전 | ❌ MQL | ✅ |
| JOIN | ✅ 완전 | 제한적 | 제한적 |
| PostgreSQL 호환 | ✅ | ❌ | ❌ |
| Write 성능 | 높음 | 보통 | 매우 높음 |
| 운영 복잡도 | 낮음 | 보통 | 높음 |

### Q2: Hypertable이 뭔가요?

**답변:**
TimescaleDB의 핵심 개념으로, **자동으로 시간 기반 파티셔닝되는 테이블**이다.

```sql
-- 일반 테이블 생성
CREATE TABLE telemetry (
    device_id TEXT NOT NULL,
    timestamp TIMESTAMPTZ NOT NULL,
    value DOUBLE PRECISION,
    metadata JSONB
);

-- Hypertable로 변환
SELECT create_hypertable(
    'telemetry',
    'timestamp',
    chunk_time_interval => INTERVAL '1 day'  -- 1일 단위 청크
);
```

**내부 구조:**
```
telemetry (Hypertable)
├── _hyper_1_1_chunk  (2024-01-01)
├── _hyper_1_2_chunk  (2024-01-02)
├── _hyper_1_3_chunk  (2024-01-03)
└── ...
```

**장점:**
- 자동 청크 생성/관리
- 청크 단위 압축/삭제 가능
- 쿼리 시 필요한 청크만 스캔

**청크 크기 설정 가이드:**
| 데이터량 | 권장 청크 크기 |
|---------|---------------|
| 초당 100건 미만 | 7일 |
| 초당 100~1,000건 | 1일 |
| 초당 1,000건 이상 | 1~4시간 |

### Q3: Continuous Aggregates는 어떻게 사용했나요?

**답변:**
**실시간으로 갱신되는 Materialized View**다.

```sql
-- 시간별 집계 뷰 생성
CREATE MATERIALIZED VIEW hourly_stats
WITH (timescaledb.continuous) AS
SELECT
    time_bucket('1 hour', timestamp) AS bucket,
    device_id,
    avg(value) AS avg_value,
    max(value) AS max_value,
    min(value) AS min_value,
    count(*) AS data_points
FROM telemetry
GROUP BY bucket, device_id;

-- 자동 갱신 정책 설정
SELECT add_continuous_aggregate_policy('hourly_stats',
    start_offset => INTERVAL '3 hours',  -- 3시간 전부터
    end_offset => INTERVAL '1 hour',     -- 1시간 전까지
    schedule_interval => INTERVAL '1 hour'  -- 1시간마다 실행
);
```

**일반 Materialized View와 차이:**

| 기준 | Materialized View | Continuous Aggregates |
|------|-------------------|----------------------|
| 갱신 방식 | 전체 새로고침 | 증분 갱신 |
| 실시간성 | REFRESH 수동 | 자동 (정책 기반) |
| 저장 공간 | 전체 복사 | 변경분만 |

**활용 사례:**
- 대시보드 차트 (시간/일별 통계)
- 이상 탐지 기준값
- 리포트 생성

### Q4: 압축은 어떻게 적용했나요?

**답변:**
TimescaleDB는 청크 단위로 압축을 지원한다.

```sql
-- 압축 활성화
ALTER TABLE telemetry SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'device_id',  -- 세그먼트 기준
    timescaledb.compress_orderby = 'timestamp DESC'  -- 정렬 순서
);

-- 자동 압축 정책 (7일 지난 청크 압축)
SELECT add_compression_policy('telemetry', INTERVAL '7 days');
```

**압축 효과:**
| 항목 | 압축 전 | 압축 후 |
|------|--------|--------|
| 저장 공간 | 100GB | 10~20GB |
| INSERT 성능 | 빠름 | 불가 (읽기 전용) |
| SELECT 성능 | 보통 | 비슷~빠름 |

**주의점:**
- 압축된 청크는 INSERT/UPDATE/DELETE 불가
- 필요시 `decompress_chunk()` 후 수정
- segmentby 컬럼 쿼리에서 필터링 권장

### Q5: MongoDB Time Series와 비교하면?

**답변:**
시계열 DB 선택 시 고려 사항을 비교한다.

| 기준 | TimescaleDB | MongoDB Time Series |
|------|-------------|---------------------|
| **쿼리 언어** | SQL | MQL (Aggregation) |
| **JOIN** | ✅ 완전 지원 | 제한적 ($lookup) |
| **복잡한 집계** | 빠름 | 느림 (3~70x) |
| **유연한 스키마** | ❌ | ✅ |
| **압축률** | 우수 | 보통 |
| **운영 복잡도** | 낮음 | 보통 |

**TimescaleDB 적합한 경우:**
- SQL 기반 분석 필요
- 복잡한 JOIN 필수 (장비 마스터 + 텔레메트리)
- PostgreSQL 생태계 활용 (JPA, 기존 도구)
- 고카디널리티 (장비 수 많음)

**MongoDB 적합한 경우:**
- 유연한 스키마 필수 (모델별 다른 센서)
- 빠른 개발 (스키마 마이그레이션 불필요)
- 소규모 (1,000대 이하)

---

## 꼬리 질문 대비

### Q: time_bucket 함수는 어떻게 사용하나요?

**답변:**
시간을 구간별로 그룹화하는 함수다.

```sql
-- 1시간 단위 집계
SELECT
    time_bucket('1 hour', timestamp) AS hour,
    device_id,
    avg(value) AS avg_value
FROM telemetry
WHERE timestamp > NOW() - INTERVAL '24 hours'
GROUP BY hour, device_id
ORDER BY hour DESC;

-- 15분 단위 집계
SELECT
    time_bucket('15 minutes', timestamp) AS bucket,
    count(*) AS data_points
FROM telemetry
GROUP BY bucket;
```

PostgreSQL의 `date_trunc`과 유사하지만 더 유연하다.

### Q: 데이터 보존 정책은 어떻게 설정하나요?

**답변:**
청크 단위로 자동 삭제 정책을 설정한다.

```sql
-- 30일 이상 된 데이터 자동 삭제
SELECT add_retention_policy('telemetry', INTERVAL '30 days');

-- 정책 확인
SELECT * FROM timescaledb_information.jobs
WHERE proc_name = 'policy_retention';
```

**계층화 전략:**
```
Hot (7일)   → 원본 데이터, 빠른 조회
Warm (90일) → 압축, 집계 뷰만 유지
Cold (이후) → S3 아카이브 또는 삭제
```

### Q: 분산 환경(Multi-node)은 어떻게 구성하나요?

**답변:**
TimescaleDB는 Multi-node 클러스터를 지원한다.

```
                  ┌─────────────────┐
                  │   Access Node   │  ← 쿼리 라우팅
                  └────────┬────────┘
           ┌───────────────┼───────────────┐
           ▼               ▼               ▼
    ┌────────────┐  ┌────────────┐  ┌────────────┐
    │ Data Node 1│  │ Data Node 2│  │ Data Node 3│
    │   Chunk 1  │  │   Chunk 2  │  │   Chunk 3  │
    └────────────┘  └────────────┘  └────────────┘
```

```sql
-- Access Node에서 Data Node 추가
SELECT add_data_node('dn1', host => 'datanode1.example.com');
SELECT add_data_node('dn2', host => 'datanode2.example.com');

-- 분산 Hypertable 생성
SELECT create_distributed_hypertable('telemetry', 'timestamp');
```

**장점:**
- 수평 확장
- 쿼리 병렬 처리
- 고가용성

### Q: PostgreSQL 네이티브 파티셔닝과 차이는?

**답변:**

| 기준 | PostgreSQL 파티셔닝 | TimescaleDB |
|------|-------------------|-------------|
| 파티션 생성 | 수동 | 자동 |
| 관리 복잡도 | 높음 | 낮음 |
| 압축 | ❌ | ✅ |
| Continuous Aggregates | ❌ | ✅ |
| time_bucket | ❌ | ✅ |

TimescaleDB는 PostgreSQL 파티셔닝 위에 시계열 최적화 기능을 추가한 것이다.

---

## 관련 개념 정리

| 개념 | 설명 |
|------|------|
| Hypertable | 자동 파티셔닝되는 시계열 테이블 |
| Chunk | Hypertable의 시간 기반 파티션 단위 |
| time_bucket | 시간 구간별 그룹화 함수 |
| Continuous Aggregates | 증분 갱신되는 집계 뷰 |
| Compression | 청크 단위 컬럼 압축 |
| Retention Policy | 자동 데이터 삭제 정책 |
| Data Node | 분산 환경에서 데이터 저장 노드 |
| Access Node | 분산 환경에서 쿼리 라우팅 노드 |

---

## 아키텍처 다이어그램

```
                    ┌─────────────────────┐
                    │   Application       │
                    │  (Spring Boot/JPA)  │
                    └──────────┬──────────┘
                               │
                    ┌──────────▼──────────┐
                    │     TimescaleDB     │
                    │   ┌───────────────┐ │
                    │   │  Hypertable   │ │
                    │   │  (telemetry)  │ │
                    │   └───────┬───────┘ │
                    │           │         │
                    │  ┌────────┼───────┐ │
                    │  ▼        ▼       ▼ │
                    │ Chunk1  Chunk2  ...│ │
                    │ (1/1)   (1/2)      │ │
                    │                     │
                    │ ┌─────────────────┐ │
                    │ │ Continuous      │ │
                    │ │ Aggregates      │ │
                    │ └─────────────────┘ │
                    └─────────────────────┘
```

**데이터 흐름:**
```
[Device] → [Kafka] → [Consumer]
                         │
              ┌──────────▼──────────┐
              │   TimescaleDB       │
              ├─────────────────────┤
              │ Hot   (7일)  원본   │
              │ Warm  (90일) 압축   │
              │ Cold  (이후) 삭제   │
              └─────────────────────┘
                         │
              ┌──────────▼──────────┐
              │   Grafana / BI      │
              └─────────────────────┘
```

---

## 블로그 링크

- [차량 텔레매틱스 데이터 파이프라인](https://gyeom.github.io/dev-notes/posts/2023-09-20-mongodb-vehicle-telemetry-pipeline/) (MongoDB vs TimescaleDB 비교 포함)
- [Kafka 대용량 메시지 처리](https://gyeom.github.io/dev-notes/posts/2023-12-08-kafka-high-volume-processing/)

---

*다음: [12-hexagonal.md](./12-hexagonal.md)*
