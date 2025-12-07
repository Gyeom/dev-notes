# 개념 정리 인덱스

interview 문서에서 다루는 핵심 개념들을 카테고리별로 정리한다.

## 문서 구조

```
concepts/
├── 00-index.md              # 이 문서
├── 01-kafka.md              # Kafka 핵심 개념
├── 02-distributed-patterns.md  # 분산 시스템 패턴
├── 03-testing.md            # 테스트 전략/패턴
├── 04-database.md           # 데이터베이스 (PostgreSQL, Redis)
├── 05-architecture.md       # 아키텍처 패턴
├── 06-spring-kotlin.md      # Spring/Kotlin 핵심
└── 07-infrastructure.md     # 인프라/모니터링
```

## 카테고리별 개념

### 1. Kafka (01-kafka.md)
- Consumer Group, Partition, Offset
- Batch Consumer, Rebalance
- DLT/DLQ, Retry 전략
- Exactly-once, At-least-once

### 2. 분산 시스템 패턴 (02-distributed-patterns.md)
- Transactional Outbox
- Saga Pattern
- Event Sourcing vs CRUD
- Dual Write Problem
- CDC (Change Data Capture)

### 3. 테스트 전략 (03-testing.md)
- Testing Pyramid vs Trophy
- Testcontainers
- Mock 패턴 (@MockBean, Mock Adapter)
- Context Caching
- Fixture, DatabaseCleanup

### 4. 데이터베이스 (04-database.md)
- PostgreSQL: EXPLAIN ANALYZE, Scan Types, Join Algorithms
- TimescaleDB: Hypertable, Continuous Aggregates
- Redis: 캐시 패턴, Stampede, TTL
- Bulk Insert, 인덱스 전략

### 5. 아키텍처 패턴 (05-architecture.md)
- Hexagonal Architecture (Port & Adapter)
- Clean Architecture
- 멀티모듈 구조
- RBAC vs ReBAC
- Rate Limiting 알고리즘

### 6. Spring/Kotlin (06-spring-kotlin.md)
- IoC/DI, @Import vs @ComponentScan
- @Transactional, AOP
- Kotlin JPA (Persistable, data class)
- profiles.include

### 7. 인프라/모니터링 (07-infrastructure.md)
- LGTM Stack (Loki, Grafana, Tempo, Mimir)
- Micrometer, OpenTelemetry
- 분산 추적, 메트릭, 로깅
- 알림 설정

## 사용법

- **면접 준비**: interview 폴더에서 STAR 형식 답변 확인
- **개념 복습**: concepts 폴더에서 핵심 정의와 비교표 확인
- **연결**: 각 개념 문서에서 관련 interview 문서 링크 제공

## 관련 링크

- [Interview 인덱스](../interview/00-index.md)
