# Transactional Outbox 패턴

## 이력서 연결

> "Transactional Outbox 패턴으로 이벤트 발행 신뢰성 확보"
> "분산 시스템에서 DB 트랜잭션과 메시지 발행의 원자성 보장"

---

## 핵심 답변 (STAR)

### Situation (상황)
- 42dot Vehicle Platform, 마이크로서비스 아키텍처
- 주문/결제 등 비즈니스 이벤트를 Kafka로 발행
- DB 커밋 후 Kafka 발행 실패 시 데이터 불일치 발생

### Task (과제)
- Dual Write Problem 해결
- DB 트랜잭션과 Kafka 발행의 원자성 보장
- 이벤트 손실 없이 At-Least-Once Delivery 구현

### Action (행동)
1. **Outbox 테이블 설계**
   - 이벤트를 DB에 먼저 저장 (같은 트랜잭션)
   - status, retry_count, next_retry_at 컬럼으로 상태 관리

2. **@TransactionalEventListener 활용**
   - BEFORE_COMMIT: Outbox 테이블에 저장
   - AFTER_COMMIT: Kafka 발행 시도

3. **Fallback 스케줄러**
   - 5초마다: 오래된 PENDING 처리 (앱 크래시 대비)
   - 60초마다: FAILED 상태 지수 백오프 재시도
   - 최대 재시도 초과 시 DEAD_LETTER로 이동

4. **모니터링**
   - Dead Letter 발생 시 Slack 알림
   - Micrometer 메트릭 (발행 성공/실패/Dead Letter 카운터)

### Result (결과)
- 이벤트 발행 신뢰성 100%
- 실패 시 자동 재시도로 운영 부담 감소
- DB에 이벤트 기록되어 디버깅 용이

---

## 예상 질문

### Q1: Dual Write Problem이 뭔가요?

**답변:**
분산 시스템에서 두 개의 서로 다른 저장소에 쓰기 작업을 할 때 발생하는 일관성 문제다.

```kotlin
@Transactional
fun createOrder(command: CreateOrderCommand) {
    val order = orderRepository.save(order)  // 1. DB 저장
    kafkaTemplate.send("order-events", event) // 2. Kafka 발행 - 여기서 문제!
}
```

| 시나리오 | 결과 | 문제 |
|----------|------|------|
| DB 성공, Kafka 실패 | 주문 저장됨, 이벤트 없음 | 다른 서비스가 주문을 모름 |
| Kafka 성공, DB 실패 | 이벤트 발행됨, 주문 없음 | 존재하지 않는 주문 이벤트 |

2PC(Two-Phase Commit)로 해결할 수 있지만, Kafka는 XA 트랜잭션을 지원하지 않고, 분산 환경에서 성능/가용성 문제가 있다.

### Q2: Outbox 패턴이 어떻게 문제를 해결하나요?

**답변:**
핵심 아이디어는 "메시지를 직접 발행하지 말고, **같은 트랜잭션 내에서 Outbox 테이블에 저장**하라"는 것이다.

```
비즈니스 로직 → Entity 저장 → Outbox 저장 (같은 트랜잭션)
                    ↓
             Message Relay → Kafka
```

- 트랜잭션 성공: Entity와 Outbox 모두 저장
- 트랜잭션 실패: Entity와 Outbox 모두 롤백

원자성이 보장되므로 데이터 불일치가 발생하지 않는다.

### Q3: Polling vs CDC 방식의 차이는?

**답변:**

**Polling Publisher:**
- 주기적으로 Outbox 테이블 조회 → PENDING 이벤트 발행
- 장점: 구현 단순, 추가 인프라 불필요
- 단점: 폴링 주기만큼 지연, DB 쿼리 부하

**CDC (Change Data Capture):**
- Debezium으로 DB 트랜잭션 로그(WAL/Binlog) 읽어서 스트리밍
- 장점: 거의 실시간 (ms 단위), DB 폴링 부하 없음
- 단점: Kafka Connect 클러스터 필요, 운영 복잡

| 기준 | Polling | CDC |
|------|---------|-----|
| 지연 | 수 초 | 수 ms |
| 인프라 | 단순 | 복잡 |
| 팀 규모 | 소규모 | 전담팀 |
| 이벤트 볼륨 | 낮음~중간 | 높음 |

### Q4: 하이브리드 방식은 어떻게 동작하나요?

**답변:**
저희는 즉시 발행 + Outbox Fallback 방식을 사용했다.

1. **빠른 경로 (정상)**: AFTER_COMMIT → 즉시 Kafka 발행 → PUBLISHED
2. **느린 경로 (실패)**: FAILED → 스케줄러가 60초마다 재시도
3. **크래시 대비**: PENDING 유지 → 스케줄러가 10초 이상 된 PENDING 처리

```kotlin
@TransactionalEventListener(phase = TransactionPhase.BEFORE_COMMIT)
fun handleBeforeCommit(command: EventPublishCommand) {
    outboxRepository.save(outboxEntity)  // 같은 트랜잭션
}

@TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
fun handleAfterCommit(command: EventPublishCommand) {
    // 비동기 발행 시도
    try {
        kafkaTemplate.send(message).get()
        updateStatus(PUBLISHED)
    } catch (e: Exception) {
        updateStatus(FAILED)  // 스케줄러가 나중에 재시도
    }
}
```

장점: 99% 이벤트가 즉시 발행, 스케줄러는 간헐적 실패만 처리

### Q5: 멱등성(Idempotency)은 어떻게 보장하나요?

**답변:**
At-Least-Once Delivery이므로 중복 발행이 발생할 수 있다. Consumer 측에서 멱등성을 보장해야 한다.

```kotlin
@KafkaListener(topics = ["order-events"])
fun handleOrderEvent(envelope: DomainEventEnvelope<OrderEvent>) {
    // eventId로 중복 체크
    if (processedEventRepository.existsById(envelope.eventId)) {
        return  // 이미 처리된 이벤트
    }

    processOrder(envelope.payload)
    processedEventRepository.save(ProcessedEvent(envelope.eventId))
}
```

또는 DB unique key + UPSERT로 처리:

```sql
INSERT INTO orders (id, status)
VALUES ($1, $2)
ON CONFLICT (id) DO UPDATE SET status = $2;
```

---

## 꼬리 질문 대비

### Q: Outbox 테이블 설계는 어떻게 했나요?

**답변:**

```sql
CREATE TABLE event_outbox (
    id              UUID PRIMARY KEY,
    aggregate_id    VARCHAR(255) NOT NULL,
    aggregate_type  VARCHAR(100) NOT NULL,
    event_type      VARCHAR(100) NOT NULL,
    topic           VARCHAR(255) NOT NULL,
    partition_key   VARCHAR(255) NOT NULL,
    payload         TEXT NOT NULL,
    status          VARCHAR(20) NOT NULL,
    retry_count     INT DEFAULT 0,
    last_error      TEXT,
    created_at      TIMESTAMPTZ NOT NULL,
    processed_at    TIMESTAMPTZ,
    next_retry_at   TIMESTAMPTZ
);

CREATE INDEX idx_outbox_status_created ON event_outbox(status, created_at);
```

핵심 설계:
- **partition_key**: 순서 보장을 위한 Kafka 파티션 키
- **status**: PENDING → PROCESSING → PUBLISHED/FAILED/DEAD_LETTER
- **next_retry_at**: 지수 백오프 재시도용

### Q: 지수 백오프 전략은?

**답변:**

```kotlin
private val RETRY_DELAYS = listOf(1L, 5L, 30L, 300L, 1800L)  // 초 단위

fun calculateNextRetry(retryCount: Int): Instant {
    val delaySeconds = RETRY_DELAYS.getOrElse(retryCount - 1) { RETRY_DELAYS.last() }
    return Instant.now().plusSeconds(delaySeconds)
}
```

재시도 간격: 1초 → 5초 → 30초 → 5분 → 30분

최대 재시도 초과 시 DEAD_LETTER로 이동하고 운영팀에 알림 발송.

### Q: 이벤트 순서 보장은 어떻게 하나요?

**답변:**
같은 Aggregate의 이벤트 순서를 보장하려면 **partition_key를 aggregate_id로 설정**한다.

```kotlin
EventPublishCommand(
    topic = "order-events",
    key = order.id.toString(),  // 같은 주문 ID → 같은 파티션
    envelope = envelope
)
```

Kafka에서 같은 파티션의 메시지는 순서가 보장된다.

### Q: BEFORE_COMMIT과 AFTER_COMMIT을 분리한 이유는?

**답변:**

**BEFORE_COMMIT에서 Outbox 저장:**
- 비즈니스 트랜잭션과 **같이 커밋/롤백**
- 트랜잭션 실패 시 Outbox도 롤백 → 고아 이벤트 없음

**AFTER_COMMIT에서 Kafka 발행:**
- 트랜잭션 **커밋 확정 후** 발행
- 발행 실패해도 Outbox에 저장되어 있으므로 나중에 재시도

만약 AFTER_COMMIT에서 Outbox 저장하면:
- 트랜잭션 커밋 후 앱 크래시 → Entity만 저장되고 이벤트 유실

### Q: Saga 패턴과 Outbox 패턴의 차이는?

**답변:**

| 패턴 | 사용 시점 | 일관성 |
|------|----------|--------|
| **Outbox** | 단일 서비스에서 이벤트 발행 | 강한 일관성 |
| **Saga** | 여러 서비스 간 분산 트랜잭션 | 최종적 일관성 |

Outbox는 "DB 저장 + 이벤트 발행"의 원자성을 보장한다.
Saga는 여러 서비스 간 보상 트랜잭션(Compensating Transaction)을 통해 일관성을 유지한다.

둘은 보완적이다. Saga의 각 스텝에서 Outbox 패턴을 사용할 수 있다.

---

## 관련 개념 정리

| 개념 | 설명 |
|------|------|
| Dual Write Problem | 두 저장소에 동시 쓰기 시 일관성 문제 |
| Transactional Outbox | 이벤트를 같은 트랜잭션 내 DB에 저장 |
| Polling Publisher | 주기적으로 Outbox 조회해서 발행 |
| CDC (Change Data Capture) | DB 로그 기반 실시간 스트리밍 |
| @TransactionalEventListener | Spring의 트랜잭션 이벤트 리스너 |
| At-Least-Once Delivery | 최소 한 번 전달 보장 (중복 가능) |
| Idempotency | 같은 요청을 여러 번 해도 결과 동일 |

---

## 아키텍처 다이어그램

```
┌─────────────────────────────────────────────────────────────┐
│                        Transaction                          │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────────┐  │
│  │  Business   │───▶│   Entity    │───▶│     Outbox      │  │
│  │   Logic     │    │   저장      │    │     저장        │  │
│  └─────────────┘    └─────────────┘    └─────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                                                   │
                              ┌────────────────────┼────────────────────┐
                              │                    │                    │
                              ▼                    ▼                    ▼
                    ┌─────────────────┐   ┌─────────────────┐   ┌──────────────┐
                    │  AFTER_COMMIT   │   │    Scheduler    │   │   Scheduler  │
                    │   즉시 발행     │   │  (PENDING 처리) │   │ (FAILED 재시도)│
                    └────────┬────────┘   └────────┬────────┘   └──────┬───────┘
                             │                     │                    │
                             └──────────┬──────────┴────────────────────┘
                                        │
                                        ▼
                               ┌─────────────────┐
                               │      Kafka      │
                               └─────────────────┘
```

---

## 상태 다이어그램

```
[생성] ──▶ PENDING ──▶ PROCESSING ──▶ PUBLISHED ──▶ [7일 후 삭제]
                │           │
                │           ▼
                │       FAILED ◀──────────────┐
                │           │                 │
                │           ▼ (retry < max)   │
                │       PROCESSING ───────────┘
                │           │
                │           ▼ (retry >= max)
                │       DEAD_LETTER ──▶ [수동 처리]
                │
                └─▶ (앱 크래시) ──▶ 스케줄러가 10초 후 처리
```

---

## 기술 선택과 Trade-off

### 왜 Outbox 패턴을 선택했는가?

**대안 비교:**

| 방식 | 일관성 | 성능 | 구현 복잡도 | 인프라 요구 |
|------|--------|------|-------------|-------------|
| **직접 발행** | 불일치 위험 | 높음 | 쉬움 | 없음 |
| **2PC (XA)** | 강한 일관성 | 낮음 | 높음 | XA 지원 필요 |
| **Outbox** | 최종 일관성 | 중간 | 중간 | 없음 |
| **Event Sourcing** | 강한 일관성 | 높음 | 매우 높음 | 이벤트 스토어 |

**Outbox 선택 이유:**
- 2PC: Kafka가 XA 트랜잭션 미지원, 성능 저하
- Event Sourcing: 기존 CRUD 시스템에 적용 비용이 너무 큼
- **Outbox가 현실적인 균형점** (추가 인프라 없이 신뢰성 확보)

### Polling vs CDC 방식

| 기준 | Polling | CDC (Debezium) |
|------|---------|----------------|
| 지연 | 수 초 | 수 ms |
| 인프라 | 단순 | Kafka Connect 클러스터 |
| 운영 복잡도 | 낮음 | 높음 |
| 팀 규모 적합 | 소규모 | 전담팀 |
| 이벤트 볼륨 | 중간 이하 | 대규모 |

**하이브리드 (즉시 발행 + Polling) 선택 이유:**
- 대부분 AFTER_COMMIT에서 즉시 발행 → 지연 최소화
- Polling은 실패/크래시 대비용 → 간헐적 실행
- CDC 도입 비용 대비 이점이 크지 않았음

### @TransactionalEventListener 설계

**BEFORE_COMMIT vs AFTER_COMMIT 분리 이유:**

| 시점 | 역할 | 실패 시 |
|------|------|---------|
| BEFORE_COMMIT | Outbox 저장 | 트랜잭션 롤백 → 데이터 일관성 유지 |
| AFTER_COMMIT | Kafka 발행 | Outbox에 저장되어 있음 → 나중에 재시도 |

**Trade-off:**
- AFTER_COMMIT에서 Outbox 저장 시: 커밋 후 앱 크래시 → 이벤트 유실
- BEFORE_COMMIT에서 Kafka 발행 시: 발행 후 롤백 → 존재하지 않는 이벤트 발행

### 재시도 전략 Trade-off

**지수 백오프 설정:**
```
1초 → 5초 → 30초 → 5분 → 30분
```

| 설정 | 빠른 재시도 | 지수 백오프 |
|------|-------------|-------------|
| 장점 | 빠른 복구 | 시스템 부하 완화 |
| 단점 | 장애 시 부하 가중 | 복구 지연 |

**지수 백오프 선택 이유:**
- 일시적 장애: 빠른 재시도로 복구
- 지속적 장애: 간격 증가로 시스템 보호
- 최대 재시도 후 Dead Letter → 운영팀 알림

### Saga vs Outbox

**사용 시점 구분:**

| 기준 | Outbox | Saga |
|------|--------|------|
| 범위 | 단일 서비스 | 여러 서비스 |
| 목적 | DB + 이벤트 원자성 | 분산 트랜잭션 조정 |
| 복잡도 | 중간 | 높음 |
| 보상 로직 | 불필요 | 필요 |

**Outbox 선택 이유:**
- 우리 요구사항: 단일 서비스에서 이벤트 발행 신뢰성
- Saga는 여러 서비스 간 트랜잭션에 필요 (오버엔지니어링 방지)

---

## 블로그 링크

- [Transactional Outbox 패턴으로 메시지 발행 신뢰성 확보하기](https://gyeom.github.io/dev-notes/posts/2024-07-15-transactional-outbox-pattern-deep-dive/)

---

*다음: [05-testcontainers.md](./05-testcontainers.md)*
