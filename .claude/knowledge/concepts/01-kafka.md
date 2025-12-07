# Kafka 핵심 개념

## 기본 구성요소

### Topic & Partition

```
Topic: order-events
├── Partition 0: [msg0, msg3, msg6, ...]
├── Partition 1: [msg1, msg4, msg7, ...]
└── Partition 2: [msg2, msg5, msg8, ...]
```

| 개념 | 설명 |
|------|------|
| **Topic** | 메시지 카테고리, 논리적 채널 |
| **Partition** | 토픽을 나눈 물리적 단위, 병렬 처리의 기본 |
| **Offset** | 파티션 내 메시지 위치 (0부터 시작) |
| **Segment** | 파티션의 물리적 파일 단위 |

### Producer

| 설정 | 설명 | 권장값 |
|------|------|--------|
| `acks` | 응답 대기 수준 | `all` (가장 안전) |
| `retries` | 실패 시 재시도 횟수 | 충분히 크게 (기본 무한) |
| `enable.idempotence` | 중복 방지 | `true` |
| `linger.ms` | 배치 대기 시간 | 5-100ms |
| `batch.size` | 배치 크기 | 16KB-1MB |

**acks 옵션:**
```
acks=0: 응답 대기 안 함 (가장 빠름, 유실 위험)
acks=1: Leader만 응답 (중간)
acks=all: 모든 ISR 응답 (가장 안전, 느림)
```

### Consumer

| 설정 | 설명 | 기본값 |
|------|------|--------|
| `group.id` | Consumer Group 식별자 | 필수 |
| `auto.offset.reset` | 오프셋 없을 때 | `latest` |
| `enable.auto.commit` | 자동 커밋 | `true` |
| `max.poll.records` | poll당 최대 레코드 | 500 |
| `max.poll.interval.ms` | poll 간 최대 간격 | 5분 |
| `session.timeout.ms` | heartbeat 기반 타임아웃 | 45초 |

---

## ISR (In-Sync Replicas)

### 정의

Leader와 동기화된 Replica 집합. 데이터 안정성의 핵심.

```
Partition 0
├── Leader (Broker 1)      ← 쓰기/읽기 담당
├── Follower (Broker 2)    ← ISR (동기화됨)
└── Follower (Broker 3)    ← ISR (동기화됨)
```

### 동작 원리

| 상황 | 동작 |
|------|------|
| Follower가 Leader 따라잡음 | ISR에 추가 |
| Follower가 뒤처짐 | ISR에서 제거 |
| Leader 장애 | ISR 중 하나가 새 Leader |
| ISR 전체 장애 | 파티션 unavailable |

### 관련 설정

| 설정 | 설명 |
|------|------|
| `min.insync.replicas` | 최소 ISR 수 (보통 2) |
| `replica.lag.time.max.ms` | ISR 탈락 기준 시간 |
| `acks=all` | 모든 ISR에 복제 후 응답 |

### acks와 ISR 조합

```
acks=all + min.insync.replicas=2

→ 최소 2개 replica에 저장되어야 성공
→ 1개만 살아있으면 쓰기 실패 (데이터 보호)
```

---

## 메시지 순서 보장

### 기본 원칙

```
✅ 파티션 내 순서 보장
❌ 파티션 간 순서 보장 없음
```

### Key 기반 파티셔닝

```kotlin
// 같은 orderId → 같은 파티션 → 순서 보장
kafkaTemplate.send("orders", orderId, orderEvent)
```

| Key | 파티션 결정 | 순서 보장 |
|-----|------------|----------|
| null | Round-robin | ❌ |
| 존재 | hash(key) % 파티션수 | ✅ (같은 key) |

### 순서 보장을 위한 설정

```properties
# Producer
max.in.flight.requests.per.connection=1  # 또는 5 with idempotence
enable.idempotence=true

# 재시도 시에도 순서 유지
```

### Hot Partition 문제

특정 key에 트래픽 집중 시 발생.

| 해결책 | 설명 |
|--------|------|
| Key에 salt 추가 | `orderId-{random}` → 분산되지만 순서 깨짐 |
| 파티션 수 증가 | 부하 분산 (완전 해결 아님) |
| 복합 key | 비즈니스 로직에 맞게 설계 |

---

## Consumer Group & Rebalance

### Consumer Group

```
Consumer Group: order-service
├── Consumer 1 → Partition 0, 1
├── Consumer 2 → Partition 2, 3
└── Consumer 3 → Partition 4, 5
```

**규칙:**
- 파티션 1개 = 최대 Consumer 1개
- Consumer > Partition → 일부 유휴
- Consumer < Partition → 하나가 여러 개 담당

### Rebalance

Consumer 추가/제거 시 파티션 재할당.

**Rebalance 트리거:**
- Consumer 추가/제거
- Consumer heartbeat 실패
- `max.poll.interval.ms` 초과
- Topic partition 변경

**Rebalance 전략:**

| 전략 | 설명 |
|------|------|
| **Range** | 연속 파티션 할당 |
| **RoundRobin** | 순환 할당 |
| **Sticky** | 기존 할당 유지 최대화 |
| **CooperativeSticky** | 점진적 재할당 (권장) |

---

## Offset 관리

### Commit 방식

| 방식 | 설정 | 장단점 |
|------|------|--------|
| **자동 커밋** | `enable.auto.commit=true` | 간편, 유실/중복 가능 |
| **수동 커밋** | `enable.auto.commit=false` | 제어 가능, 복잡 |

### 수동 커밋 코드

```kotlin
@KafkaListener(topics = ["orders"])
fun consume(records: List<ConsumerRecord<String, String>>, ack: Acknowledgment) {
    try {
        process(records)
        ack.acknowledge()  // 성공 시에만 커밋
    } catch (e: Exception) {
        // 커밋 안 함 → 재처리
    }
}
```

### auto.offset.reset

| 값 | 동작 |
|----|------|
| `earliest` | 가장 처음부터 |
| `latest` | 가장 최신부터 (기본) |
| `none` | 오프셋 없으면 에러 |

---

## 배치 처리

### Batch Consumer 설정

```yaml
spring:
  kafka:
    consumer:
      max-poll-records: 500
    listener:
      type: batch
      ack-mode: manual
```

### 배치 크기 결정 기준

| 고려사항 | 설명 |
|----------|------|
| 메모리 | 메시지 크기 × batch size |
| 처리 시간 | max.poll.interval.ms 내 완료 |
| DB 효율 | Bulk Insert 최적 구간 (100-1000) |
| 에러 단위 | 배치 전체 재처리 |

---

## DLT/DLQ (Dead Letter)

### 용어

| 용어 | 설명 |
|------|------|
| **DLT** | Dead Letter Topic (Kafka 토픽) |
| **DLQ** | Dead Letter Queue (일반적 용어) |

### @RetryableTopic

```kotlin
@RetryableTopic(
    attempts = "4",
    backoff = @Backoff(delay = 1000, multiplier = 2.0),
    dltTopicSuffix = "-dlt"
)
@KafkaListener(topics = ["orders"])
fun consume(message: OrderMessage) {
    // 실패 시 자동으로 retry topic → DLT
}
```

**생성되는 토픽:**
```
orders (원본)
orders-retry-0 (1차 재시도)
orders-retry-1 (2차 재시도)
orders-dlt (Dead Letter)
```

### 재시도 전략 비교

| 방식 | 구현 복잡도 | 유연성 | 블로킹 |
|------|-------------|--------|--------|
| **@RetryableTopic** | 쉬움 | 낮음 | 낮음 |
| **SeekToCurrentErrorHandler** | 중간 | 중간 | 높음 |
| **수동 재시도** | 높음 | 높음 | 선택 |

---

## 메시지 전달 보장

### 전달 수준

| 수준 | 설명 | 구현 |
|------|------|------|
| **At-most-once** | 최대 1번 (유실 가능) | 처리 전 커밋 |
| **At-least-once** | 최소 1번 (중복 가능) | 처리 후 커밋 |
| **Exactly-once** | 정확히 1번 | 트랜잭션 + 멱등성 |

### Exactly-once 구현

```kotlin
// Producer
props["enable.idempotence"] = true
props["transactional.id"] = "my-transactional-id"

// Consumer
props["isolation.level"] = "read_committed"
```

### 실무에서의 선택

**At-least-once + 멱등성**이 가장 현실적:
- Exactly-once: 성능 저하, 복잡
- At-most-once: 데이터 유실
- **At-least-once + UPSERT**: 간단하고 안전

```sql
INSERT INTO orders (id, status)
VALUES ($1, $2)
ON CONFLICT (id) DO UPDATE SET status = $2;
```

---

## Idempotent Producer

### 동작 원리

```
Producer → Broker
  │
  ├─ PID (Producer ID): 프로듀서 고유 식별자
  └─ Sequence Number: 메시지별 순번

Broker 측:
  - (PID, Partition, SeqNum) 조합으로 중복 감지
  - 이미 받은 SeqNum이면 무시
```

### 설정

```properties
enable.idempotence=true  # Kafka 3.0+에서 기본값

# 자동으로 설정됨
acks=all
retries=Integer.MAX_VALUE
max.in.flight.requests.per.connection=5
```

### 한계

| 상황 | 보장 |
|------|------|
| 단일 파티션, 프로듀서 정상 | ✅ 중복 방지 |
| 프로듀서 재시작 | ❌ 새 PID 발급 |
| 여러 파티션 원자적 쓰기 | ❌ 트랜잭션 필요 |

---

## Kafka Transaction

### 목적

여러 파티션에 **원자적**으로 메시지 쓰기.

```
BEGIN
  send(topic-A, partition-0, msg1)
  send(topic-B, partition-1, msg2)
COMMIT  ← 둘 다 성공하거나 둘 다 실패
```

### Producer 설정

```kotlin
props["transactional.id"] = "order-service-tx-1"
props["enable.idempotence"] = true  // 자동 활성화

val producer = KafkaProducer<String, String>(props)
producer.initTransactions()

producer.beginTransaction()
try {
    producer.send(record1)
    producer.send(record2)
    producer.commitTransaction()
} catch (e: Exception) {
    producer.abortTransaction()
}
```

### Consumer 설정

```properties
isolation.level=read_committed  # 커밋된 메시지만 읽음
```

| isolation.level | 동작 |
|-----------------|------|
| `read_uncommitted` | 모든 메시지 읽음 (기본) |
| `read_committed` | 커밋된 메시지만 읽음 |

### Kafka Streams EOS

```properties
processing.guarantee=exactly_once_v2
```

Kafka Streams는 내부적으로 트랜잭션을 사용하여 read-process-write를 원자적으로 처리.

---

## Rebalance 최적화

### Rebalance Storm 원인

| 원인 | 설명 |
|------|------|
| 잦은 Consumer 재시작 | 매번 rebalance 발생 |
| 긴 처리 시간 | `max.poll.interval.ms` 초과 |
| 불안정한 네트워크 | heartbeat 실패 |

### 해결책

**1. Static Membership**

```properties
group.instance.id=consumer-1  # 고정 ID
session.timeout.ms=300000     # 5분 (재시작 여유)
```

Consumer 재시작해도 같은 ID면 파티션 유지.

**2. Cooperative Rebalancing**

```properties
partition.assignment.strategy=
  org.apache.kafka.clients.consumer.CooperativeStickyAssignor
```

점진적 재할당으로 Stop-the-World 방지.

**3. 적절한 타임아웃**

| 설정 | 권장 |
|------|------|
| `session.timeout.ms` | 45초 (기본) |
| `heartbeat.interval.ms` | 15초 (session의 1/3) |
| `max.poll.interval.ms` | 처리 시간에 맞게 |

---

## Log Compaction

### 개념

동일 key의 최신 메시지만 유지.

```
Before Compaction:
key=A: v1 → v2 → v3
key=B: v1 → v2

After Compaction:
key=A: v3
key=B: v2
```

### 설정

```properties
cleanup.policy=compact  # 또는 delete,compact

# Compaction 주기/조건
min.cleanable.dirty.ratio=0.5
segment.ms=604800000  # 7일
```

### 사용 사례

| 사용 사례 | 설명 |
|----------|------|
| CDC | 최신 상태만 필요 |
| Cache 동기화 | 최종 값만 필요 |
| Materialized View | 집계 결과 저장 |

### 주의사항

- Tombstone (value=null): key 삭제 마커
- 순서 보장: 같은 key 내에서만
- 공간 효율: 중복 제거로 저장 공간 절약

---

## 관련 Interview 문서

- [02-kafka-batch-processing.md](../interview/02-kafka-batch-processing.md)
- [03-kafka-dlt-dlq.md](../interview/03-kafka-dlt-dlq.md)

---

*다음: [02-distributed-patterns.md](./02-distributed-patterns.md)*
