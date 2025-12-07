# 면접 준비 인덱스

## 개요

이력서 기반 면접 질문 대비 자료. 각 주제별로 예상 질문, 핵심 답변, 꼬리 질문, 관련 개념을 정리한다.

## 목차

### 1. 자기소개 및 경력 요약
- [01-introduction.md](./01-introduction.md) - 자기소개, 강점, 지원 동기

### 2. Kafka & 메시징
- [02-kafka-batch-processing.md](./02-kafka-batch-processing.md) - 대용량 처리 (Batch Consumer, Bulk Insert)
- [03-kafka-dlt-dlq.md](./03-kafka-dlt-dlq.md) - DLT/DLQ 재처리 전략
- [04-outbox-pattern.md](./04-outbox-pattern.md) - Transactional Outbox 패턴

### 3. 테스팅
- [05-testcontainers.md](./05-testcontainers.md) - Testcontainers 기반 통합 테스트
- [06-testing-strategy.md](./06-testing-strategy.md) - 테스트 피라미드, Mock 전략

### 4. 인가/보안
- [07-openfga-rebac.md](./07-openfga-rebac.md) - OpenFGA, ReBAC 설계
- [08-rate-limiting.md](./08-rate-limiting.md) - Rate Limiting (Token Bucket)

### 5. 데이터베이스
- [09-redis-caching.md](./09-redis-caching.md) - Redis 캐싱 전략
- [10-postgresql.md](./10-postgresql.md) - PostgreSQL 최적화, EXPLAIN ANALYZE
- [11-timescaledb.md](./11-timescaledb.md) - 시계열 데이터 처리

### 6. 아키텍처
- [12-hexagonal.md](./12-hexagonal.md) - Hexagonal Architecture
- [13-multi-module.md](./13-multi-module.md) - 멀티모듈 설계

### 7. Kotlin/Spring
- [14-kotlin-jpa.md](./14-kotlin-jpa.md) - Kotlin JPA 엔티티 설계
- [15-spring-core.md](./15-spring-core.md) - Spring 핵심 개념

### 8. DevOps/Observability
- [16-observability.md](./16-observability.md) - LGTM 스택, Micrometer, Grafana

### 9. Behavioral
- [17-problem-solving.md](./17-problem-solving.md) - 문제 해결 사례
- [18-collaboration.md](./18-collaboration.md) - 협업, 갈등 해결
- [19-growth.md](./19-growth.md) - 성장, 학습 경험

---

## 이력서 핵심 수치

| 항목 | 수치 | 맥락 |
|------|------|------|
| 데이터 처리량 | 분당 50만 건 | 한화솔루션 Telemetry |
| 장비 규모 | 50만대 | 한화솔루션 HEMS |
| 데이터 정합성 | 98% → 100% | DLT 기반 재처리 |
| 테스트 커버리지 | 90% | 42dot Vehicle Platform |
| 캐시 Hit Rate | 90%+ | Redis Cache-Aside |
| E2E 테스트 | 300여 개 | 글로벌 API |
| 앱 다운로드 | 50만+ | 롯데 WYD |
| 앱 안정성 | 99%+ | Crashlytics |

## 회사별 핵심 키워드

### 42dot (2024.05 ~ 현재)
- Vehicle Platform, SDV, EU Data Act
- Outbox 패턴, DLQ, OpenFGA
- Testcontainers, 커버리지 90%
- Rate Limiting, LGTM 스택

### 한화솔루션 (2021.05 ~ 2024.04)
- HEMS, Telemetry, 대용량 처리
- Kafka Batch Consumer, Bulk Insert
- DLT 재처리, 글로벌 API (Timezone/DST)
- Redis 캐싱, Spring Camp 발표

### 롯데정보통신 (2019.07 ~ 2021.05)
- WYD 라이브 커머스, Android
- Multi Module, Crashlytics
- GA, Adbrix

## 예상 질문 빈도 (우선순위)

1. **Kafka 대용량 처리** - 핵심 성과, 구체적 숫자
2. **테스트 전략** - 90% 커버리지, Testcontainers
3. **Outbox 패턴** - 분산 시스템 이해도
4. **OpenFGA/ReBAC** - 최신 기술 차별화
5. **Redis 캐싱** - 성능 최적화
6. **Hexagonal Architecture** - 설계 철학
7. **문제 해결 사례** - Behavioral

## 답변 프레임워크

### STAR 기법
- **S**ituation: 상황/배경
- **T**ask: 해결해야 할 과제
- **A**ction: 내가 취한 행동
- **R**esult: 결과 및 배운 점

### 기술 질문 답변 구조
1. 한 줄 정의
2. 왜 사용했는지 (문제 상황)
3. 어떻게 구현했는지
4. 결과/효과
5. 트레이드오프/한계

---

*마지막 업데이트: 2025-12-07*
