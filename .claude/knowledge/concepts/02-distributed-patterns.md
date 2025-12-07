# 분산 시스템 패턴

## CAP Theorem

### 정의

분산 시스템은 **Consistency, Availability, Partition Tolerance** 중 **2개만** 동시에 보장할 수 있다.

```
        Consistency
           /\
          /  \
         /    \
        /  CA  \
       /--------\
      / CP    AP \
     /______________\
Partition        Availability
Tolerance
```

### 세 가지 속성

| 속성 | 설명 | 예시 |
|------|------|------|
| **Consistency** | 모든 노드가 동일한 데이터 반환 | 읽기 시 최신 쓰기 결과 보장 |
| **Availability** | 모든 요청에 응답 (에러 아님) | 노드 장애에도 서비스 가능 |
| **Partition Tolerance** | 네트워크 분할에도 동작 | 노드 간 통신 실패 허용 |

### 실제 선택

**P(Partition Tolerance)는 필수** → 실제로는 C와 A 중 선택.

| 선택 | 설명 | 예시 |
|------|------|------|
| **CP** | 일관성 우선, 가용성 희생 | 금융, 재고 시스템 |
| **AP** | 가용성 우선, 일관성 희생 | SNS 피드, 장바구니 |

---

## PACELC Theorem

CAP의 확장. **파티션이 없을 때**도 Trade-off 존재.

```
if Partition:
    choose between Availability and Consistency
else:
    choose between Latency and Consistency
```

### 시스템 분류

| 시스템 | 분류 | 설명 |
|--------|------|------|
| Cassandra | PA/EL | 파티션 시 가용성, 평상시 낮은 지연 |
| MongoDB | PA/EC | 파티션 시 가용성, 평상시 일관성 |
| HBase | PC/EC | 항상 일관성 우선 |
| CockroachDB | PC/EC | 강한 일관성, 성능 희생 |

### 면접 포인트

```
Q: "이커머스 플랫폼 DB 설계 시 일관성 vs 가용성?"

A: "재고는 CP (과판매 방지),
    상품 리뷰는 AP (잠시 지연 허용)"
```

---

## 2PC (Two-Phase Commit)

### 동작 방식

```
Phase 1: Prepare (투표)
  Coordinator → "준비됐나요?" → Participant 1, 2, 3
  Participants → "준비됐습니다" or "못하겠습니다"

Phase 2: Commit/Abort
  if 모두 준비됨:
    Coordinator → "커밋하세요" → All
  else:
    Coordinator → "취소하세요" → All
```

### 장단점

| 장점 | 단점 |
|------|------|
| 강한 일관성 (ACID) | 동기 방식 (블로킹) |
| 원자성 보장 | Coordinator가 SPOF |
| 표준 프로토콜 | 확장성 낮음 |

### 실패 시나리오

| 상황 | 결과 |
|------|------|
| Participant 장애 (Phase 1) | Abort |
| Participant 장애 (Phase 2) | 복구 후 Commit/Abort |
| Coordinator 장애 | **블로킹** (Participant가 대기) |

---

## Saga vs 2PC 비교

| 기준 | 2PC | Saga |
|------|-----|------|
| 일관성 | 강한 일관성 | 최종 일관성 |
| 격리 수준 | 높음 (락) | 없음 |
| 성능 | 느림 (동기) | 빠름 (비동기) |
| 확장성 | 낮음 | 높음 |
| 복구 방식 | Rollback | 보상 트랜잭션 |
| 적합한 상황 | 단기 트랜잭션 | 장기 트랜잭션 |

### 하이브리드 접근

```
핵심 금융 로직 → 2PC (정확성 우선)
주변 서비스 → Saga (성능 우선)
```

---

## Dual Write Problem

### 문제 정의

두 개의 서로 다른 저장소에 쓰기 작업 시 일관성 문제 발생.

```kotlin
@Transactional
fun createOrder(command: CreateOrderCommand) {
    orderRepository.save(order)           // 1. DB 저장
    kafkaTemplate.send("orders", event)   // 2. Kafka 발행 - 문제!
}
```

| 시나리오 | 결과 |
|----------|------|
| DB 성공, Kafka 실패 | 주문 있음, 이벤트 없음 |
| Kafka 성공, DB 실패 | 이벤트 있음, 주문 없음 |

### 해결책 비교

| 방식 | 일관성 | 복잡도 | 성능 |
|------|--------|--------|------|
| 2PC (XA) | 강함 | 높음 | 낮음 |
| Outbox Pattern | 최종 일관성 | 중간 | 중간 |
| Event Sourcing | 강함 | 매우 높음 | 높음 |
| Saga | 최종 일관성 | 높음 | 중간 |

---

## Transactional Outbox Pattern

### 핵심 아이디어

> 메시지를 직접 발행하지 말고, 같은 트랜잭션 내에서 Outbox 테이블에 저장하라.

```
비즈니스 로직 → Entity 저장 → Outbox 저장 (같은 트랜잭션)
                    ↓
             Message Relay → Kafka
```

### Outbox 테이블 설계

```sql
CREATE TABLE event_outbox (
    id              UUID PRIMARY KEY,
    aggregate_type  VARCHAR(100) NOT NULL,
    aggregate_id    VARCHAR(255) NOT NULL,
    event_type      VARCHAR(100) NOT NULL,
    topic           VARCHAR(255) NOT NULL,
    payload         JSONB NOT NULL,
    status          VARCHAR(20) NOT NULL,  -- PENDING, PUBLISHED, FAILED
    retry_count     INT DEFAULT 0,
    created_at      TIMESTAMPTZ NOT NULL,
    published_at    TIMESTAMPTZ
);

CREATE INDEX idx_outbox_status ON event_outbox(status, created_at);
```

### 발행 방식

| 방식 | 지연 | 인프라 | 적합한 상황 |
|------|------|--------|-------------|
| **Polling** | 수 초 | 단순 | 소규모, 팀 작음 |
| **CDC (Debezium)** | 수 ms | Kafka Connect | 대규모, 실시간 |
| **하이브리드** | 수 ms | 중간 | 범용적 |

### 하이브리드 방식

```kotlin
@TransactionalEventListener(phase = BEFORE_COMMIT)
fun saveToOutbox(event: DomainEvent) {
    outboxRepository.save(event.toOutbox())  // 같은 트랜잭션
}

@TransactionalEventListener(phase = AFTER_COMMIT)
fun publishImmediately(event: DomainEvent) {
    try {
        kafkaTemplate.send(event).get()
        updateStatus(PUBLISHED)
    } catch (e: Exception) {
        updateStatus(FAILED)  // 스케줄러가 나중에 재시도
    }
}
```

---

## Saga Pattern

### 정의

여러 서비스에 걸친 트랜잭션을 보상 트랜잭션(Compensating Transaction)으로 관리.

### Choreography vs Orchestration

```
Choreography (이벤트 기반):
Order → [OrderCreated] → Inventory → [Reserved] → Payment → [Paid]
                              ↓
                        [ReserveFailed] → Order (보상)

Orchestration (중앙 조정자):
Saga Orchestrator
├── 1. Order Service: Create Order
├── 2. Inventory Service: Reserve
├── 3. Payment Service: Charge
└── 실패 시: 역순으로 보상
```

| 방식 | 결합도 | 가시성 | 복잡도 |
|------|--------|--------|--------|
| **Choreography** | 낮음 | 낮음 | 서비스 늘면 복잡 |
| **Orchestration** | 높음 | 높음 | 조정자에 집중 |

### Outbox vs Saga

| 패턴 | 범위 | 목적 |
|------|------|------|
| **Outbox** | 단일 서비스 | DB + 이벤트 원자성 |
| **Saga** | 여러 서비스 | 분산 트랜잭션 |

둘은 보완적: Saga의 각 스텝에서 Outbox 사용 가능.

---

## Event Sourcing

### 핵심 개념

상태가 아니라 이벤트를 저장한다.

```
전통적 (상태 저장):
Account { balance: 150 }

Event Sourcing (이벤트 저장):
AccountCreated { id: 1 }
Deposited { amount: 100 }
Deposited { amount: 100 }
Withdrawn { amount: 50 }
→ 현재 상태: balance = 150
```

### 구성요소

| 개념 | 설명 |
|------|------|
| **Event Store** | 이벤트 저장소 (Append-only) |
| **Aggregate** | 이벤트를 적용해 상태 재구성 |
| **Projection** | 이벤트를 읽기 모델로 변환 |
| **Snapshot** | 특정 시점 상태 저장 (성능) |

### Trade-off

| 장점 | 단점 |
|------|------|
| 완전한 이력 | 학습 곡선 높음 |
| 감사/디버깅 용이 | 쿼리 복잡 (CQRS 필요) |
| 시점 재현 가능 | 스키마 변경 어려움 |

---

## CDC (Change Data Capture)

### 정의

데이터베이스 변경 로그를 실시간으로 캡처.

```
PostgreSQL WAL → Debezium → Kafka → Consumer
```

### 활용

| 용도 | 설명 |
|------|------|
| **Outbox 발행** | Outbox 테이블 변경 감지 → Kafka |
| **데이터 동기화** | DB → Elasticsearch |
| **캐시 무효화** | DB 변경 → Redis 무효화 |
| **감사 로그** | 모든 변경 기록 |

### Debezium 설정 (Outbox용)

```json
{
  "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
  "table.include.list": "public.event_outbox",
  "transforms": "outbox",
  "transforms.outbox.type": "io.debezium.transforms.outbox.EventRouter"
}
```

---

## 일관성 모델

### 강한 일관성 vs 최종 일관성

| 모델 | 설명 | 예시 |
|------|------|------|
| **Strong** | 즉시 모든 노드에 반영 | 2PC, Paxos |
| **Eventual** | 언젠가 일치 | Outbox, Saga |
| **Causal** | 인과관계 유지 | 벡터 클록 |

### 실무 선택

**최종 일관성 + 보상** 선호:
- 강한 일관성: 성능 저하, 가용성 감소
- 최종 일관성: 빠르고 확장 가능
- 보상 로직으로 불일치 해소

---

## 멱등성 (Idempotency)

### 정의

같은 요청을 여러 번 해도 결과가 동일.

### 구현 방식

| 방식 | 구현 | 장단점 |
|------|------|--------|
| **Unique Key + UPSERT** | DB 제약 | 간단, DB 부하 |
| **Idempotency Key 저장** | 별도 테이블 | 유연, 추가 저장 |
| **Redis 중복 체크** | TTL 기반 | 빠름, 만료 주의 |

```kotlin
// DB Unique Key
INSERT INTO orders (id, status)
VALUES ($1, $2)
ON CONFLICT (id) DO UPDATE SET status = $2;

// Idempotency Key
if (processedEventRepository.existsById(eventId)) {
    return  // 이미 처리됨
}
process(event)
processedEventRepository.save(eventId)
```

---

## 분산 락 (Distributed Lock)

### 필요성

여러 인스턴스가 동시에 같은 리소스에 접근할 때 동시성 제어.

### Redis 기반 구현 (Redisson)

```kotlin
val lock = redisson.getLock("order:${orderId}")

if (lock.tryLock(10, 30, TimeUnit.SECONDS)) {
    try {
        // 크리티컬 섹션
        processOrder(orderId)
    } finally {
        lock.unlock()
    }
}
```

### Redlock 알고리즘

```
5개 Redis 노드 중 과반수(3개 이상)에서 락 획득 성공 시 유효
```

| 장점 | 단점 |
|------|------|
| 단일 노드 장애 허용 | 복잡한 구현 |
| 높은 가용성 | 클럭 드리프트 문제 |

### 주의사항

| 문제 | 해결 |
|------|------|
| 락 만료 전 작업 미완료 | TTL 충분히, Watchdog |
| 데드락 | 타임아웃 필수 |
| Split Brain | Redlock 또는 Consensus |

---

## Leader Election

### 목적

분산 시스템에서 **하나의 리더**만 특정 작업 수행.

### 방식

| 방식 | 도구 | 설명 |
|------|------|------|
| Consensus 기반 | ZooKeeper, etcd | Paxos/Raft 알고리즘 |
| Lock 기반 | Redis, DB | 분산 락으로 리더 선출 |
| Lease 기반 | Kubernetes | 주기적 갱신 필요 |

### ZooKeeper 예시

```
/election
├── node_0001 (Leader)
├── node_0002
└── node_0003

가장 작은 번호가 Leader
Leader 삭제되면 다음 번호가 승계
```

---

## Consistent Hashing

### 문제

노드 추가/제거 시 **모든** 데이터 재배치.

```
hash(key) % N → N 변경 시 전체 재배치
```

### 해결

```
        0
       /|\
      / | \
    330  30
     |    |
 Node A  Node B
     |    |
    270  90
      \ | /
       \|/
       180
      Node C

Key가 시계방향으로 가장 가까운 노드에 저장
노드 추가/제거 시 일부만 재배치
```

### Virtual Node

| 문제 | 해결 |
|------|------|
| 불균등 분포 | 노드당 여러 Virtual Node |
| Hot Spot | 가상 노드로 분산 |

### 사용 사례

- Cassandra, DynamoDB
- Redis Cluster
- CDN

---

## Circuit Breaker

### 상태 머신

```
     실패 임계치 도달
CLOSED ──────────────→ OPEN
   ↑                      │
   │ 성공                  │ 타임아웃
   │                      ↓
   └────────────── HALF-OPEN
       테스트 성공
```

### 구현 (Resilience4j)

```kotlin
val circuitBreaker = CircuitBreaker.ofDefaults("paymentService")

val result = circuitBreaker.executeSupplier {
    paymentClient.charge(order)
}
```

### 설정

| 설정 | 설명 | 권장값 |
|------|------|--------|
| `failureRateThreshold` | 실패율 임계치 | 50% |
| `waitDurationInOpenState` | Open 유지 시간 | 60초 |
| `slidingWindowSize` | 측정 윈도우 | 100 |

---

## Bulkhead Pattern

### 개념

장애 격리를 위해 리소스를 분리.

```
┌─────────────────────────────┐
│        Application          │
├─────────┬─────────┬─────────┤
│ Pool A  │ Pool B  │ Pool C  │
│ (10)    │ (10)    │ (10)    │
└─────────┴─────────┴─────────┘

Service A 장애 → Pool A만 소진
Service B, C는 정상 동작
```

### 구현 방식

| 방식 | 설명 |
|------|------|
| Thread Pool | 서비스별 스레드 풀 분리 |
| Semaphore | 동시 요청 수 제한 |
| Connection Pool | DB/HTTP 커넥션 분리 |

---

## Retry with Backoff

### Exponential Backoff

```kotlin
val retryConfig = RetryConfig.custom<Any>()
    .maxAttempts(5)
    .waitDuration(Duration.ofMillis(1000))
    .retryOnException { it is TransientException }
    .intervalFunction(IntervalFunction.ofExponentialBackoff())
    .build()

// 재시도 간격: 1s → 2s → 4s → 8s → 16s
```

### Jitter 추가

```
Without Jitter: 1s, 2s, 4s, 8s (모든 클라이언트 동시 재시도)
With Jitter: 1.2s, 1.8s, 4.5s, 7.3s (분산)
```

### 재시도 대상 구분

| 재시도 O | 재시도 X |
|----------|----------|
| 네트워크 타임아웃 | 400 Bad Request |
| 503 Service Unavailable | 401 Unauthorized |
| 429 Too Many Requests | 비즈니스 로직 실패 |

---

## 관련 Interview 문서

- [04-outbox-pattern.md](../interview/04-outbox-pattern.md)
- [03-kafka-dlt-dlq.md](../interview/03-kafka-dlt-dlq.md)

---

## 참고 자료

- [Martin Fowler - Circuit Breaker](https://martinfowler.com/bliki/CircuitBreaker.html)
- [CAP Theorem Explained](https://blog.algomaster.io/p/cap-theorem-explained)
- [Saga Pattern vs 2PC](https://www.baeldung.com/cs/two-phase-commit-vs-saga-pattern)

---

*다음: [03-testing.md](./03-testing.md)*
