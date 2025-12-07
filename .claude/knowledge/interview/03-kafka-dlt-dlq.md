# Kafka DLT/DLQ 재처리 전략

## 이력서 연결

> "DLT 기반 재처리 메커니즘으로 데이터 정합성 98% → 100%"
> "Transactional Outbox 패턴, DLQ 기반 신뢰성 있는 이벤트 발행"

---

## 핵심 답변 (STAR)

### Situation (상황)
- 한화솔루션 Telemetry 시스템, 분당 50만 건 처리
- 일부 메시지 처리 실패 시 데이터 유실 발생
- 데이터 정합성 98% → 비즈니스 리포트 신뢰도 문제

### Task (과제)
- 실패한 메시지 안전하게 격리
- 재시도 로직 체계화
- 100% 데이터 정합성 달성

### Action (행동)
1. **@RetryableTopic 도입**
   - 5회 재시도, 지수 백오프 (5초 → 10초 → 20초 → 40초 → 80초)
   - Non-Retryable 예외 분류 (역직렬화 실패 등)

2. **Dead Letter Topic 설계**
   - `{topic-name}.dlt` 토픽 자동 생성
   - `@DltHandler`로 DLT 메시지 처리
   - 알림 발송 + DB 저장

3. **하이브리드 전략 (42dot)**
   - Kafka DLT → PostgreSQL 저장
   - SQL로 실패 메시지 조회/분석
   - 선택적 재처리 (원본 토픽 재발행)

4. **동적 리스너 제어**
   - Kafka 토픽을 통해 모든 인스턴스에 제어 메시지 브로드캐스트
   - `KafkaListenerEndpointRegistry`로 리스너 시작/중지

### Result (결과)
- 데이터 정합성 98% → 100%
- 실패 원인 분석 시간 단축 (SQL 조회)
- 운영자 재처리 API로 신속한 대응

---

## 예상 질문

### Q1: DLT(Dead Letter Topic)가 뭔가요?

**답변:**
재시도에도 불구하고 처리에 실패한 메시지를 저장하는 Kafka 토픽이다. '마지막 피난처'로서:

- 실패 메시지의 안전한 격리
- 메인 데이터 스트림 방해 최소화
- 실패 원인 분석 및 디버깅 가능

Spring Kafka에서는 `@RetryableTopic`과 `@DltHandler`로 선언적으로 구현한다.

### Q2: 왜 98%에서 100%로 올릴 수 있었나요?

**답변:**
기존 문제:
- 재시도 없이 바로 실패 → 일시적 오류도 유실
- 실패 메시지 추적 불가

개선:
1. **지수 백오프 재시도**: 일시적 장애 극복
2. **DLT 분리**: 영구 실패 메시지 격리
3. **DB 저장**: 실패 원인 분석 → 코드 수정 → 재처리
4. **알림 시스템**: 즉시 인지 및 대응

### Q3: Retryable vs Non-Retryable 예외를 어떻게 구분하나요?

**답변:**

**Retryable 예외** (재시도로 해결 가능):
- 네트워크 타임아웃
- 외부 API 일시 장애
- DB 연결 실패
- Rate Limit 초과

**Non-Retryable 예외** (재시도해도 해결 불가):
- 메시지 역직렬화 실패 (`DeserializationException`)
- 데이터 유효성 검증 실패
- 비즈니스 로직 오류
- 메시지 형식 불일치

```kotlin
@RetryableTopic(
    exclude = [
        DeserializationException::class,
        MessageConversionException::class,
        ValidationException::class
    ]
)
```

Spring Kafka는 `DeserializationException`, `MessageConversionException`을 기본적으로 fatal로 처리하여 재시도하지 않는다.

### Q4: 지수 백오프(Exponential Backoff)는 왜 사용하나요?

**답변:**
고정 간격 재시도의 문제:
- 외부 서비스 장애 시 지속적인 부하
- 복구 기회 없이 재시도 소진

지수 백오프의 장점:
- 서비스 복구 시간 확보
- 시스템 부하 완화
- 점진적으로 간격 증가 (5초 → 10초 → 20초 → 40초)

```kotlin
backoff = Backoff(delay = 5000, multiplier = 2.0)
```

### Q5: 하이브리드 전략(Kafka DLT + DB)을 선택한 이유는?

**답변:**

**Kafka DLT만 사용 시 문제:**
- DLT 메시지 조회가 불편 (별도 Consumer 필요)
- 특정 메시지만 선택적 재처리 어려움
- 운영자가 메시지 내용 확인/수정 어려움

**하이브리드의 장점:**
- SQL로 즉시 조회/분석
- 선택적 재처리 (특정 ID만 골라서)
- 메시지 수정 후 재발행 가능
- 감사 로그 (누가, 언제, 어떻게 처리)

Robinhood, Uber도 동일한 패턴을 사용한다.

---

## 꼬리 질문 대비

### Q: DLT 재처리는 어떻게 하나요?

**답변:**
두 가지 방식:

1. **Consumer 재시작**: DLT Consumer를 다시 시작하면 offset부터 재처리
2. **원본 토픽 재발행 (권장)**:
   - DB에서 실패 메시지 조회
   - 원본 토픽으로 재발행
   - 기존 Consumer가 그대로 처리

```kotlin
kafkaTemplate.send(
    record.originalTopic,
    record.messageKey,
    record.payload
)
```

### Q: 분산 환경에서 리스너를 어떻게 제어하나요?

**답변:**
여러 인스턴스가 동시에 운영되므로, Kafka 토픽을 통해 제어 메시지를 브로드캐스트한다.

```kotlin
// 모든 파티션에 제어 메시지 발행
partitions.forEach { partition ->
    kafkaTemplate.send(ProducerRecord("kafka.control", partition, message))
}

// 각 인스턴스에서 수신
@KafkaListener(topics = ["kafka.control"])
fun handleControlMessage(record: ConsumerRecord<String, String>) {
    val request = objectMapper.readValue(record.value(), ListenerControlRequest::class.java)
    val container = registry.getListenerContainer(request.listenerId)

    when (request.action) {
        START -> container.start()
        STOP -> container.stop()
    }
}
```

### Q: DLT 처리 자체가 실패하면 어떻게 되나요?

**답변:**
`DltStrategy` 설정에 따라 다르다:

| 전략 | 동작 | 사용 시점 |
|------|------|----------|
| `ALWAYS_RETRY_ON_ERROR` | DLT로 다시 전송 (기본값) | 일시적 오류 예상 |
| `FAIL_ON_ERROR` | 처리 중단 | DLT 처리 반드시 성공 필요 |
| `NO_DLT` | DLT 없이 재시도만 | 특수 케이스 |

### Q: DLQ vs DLT 차이가 뭔가요?

**답변:**
개념적으로 동일하다. 명명 차이:

- **DLT (Dead Letter Topic)**: Kafka에서 주로 사용하는 용어
- **DLQ (Dead Letter Queue)**: RabbitMQ, SQS 등에서 사용하는 용어

둘 다 "실패한 메시지를 격리하는 저장소"라는 점에서 같다.

### Q: 멱등성(Idempotency)은 어떻게 보장하나요?

**답변:**
재처리 시 중복 발생 가능성이 있으므로:

1. **DB unique key**: `UPSERT`로 중복 방지
2. **메시지 ID 기반**: 처리 완료 ID를 별도 테이블에 기록
3. **Kafka Idempotent Producer**: `enable.idempotence=true`

```sql
INSERT INTO telemetry (device_id, timestamp, value)
VALUES ($1, $2, $3)
ON CONFLICT (device_id, timestamp)
DO UPDATE SET value = $3;
```

---

## 관련 개념 정리

| 개념 | 설명 |
|------|------|
| DLT/DLQ | 재시도 실패 메시지 격리 저장소 |
| Exponential Backoff | 재시도 간격을 지수적으로 증가 |
| @RetryableTopic | Spring Kafka의 선언적 재시도 어노테이션 |
| @DltHandler | DLT 메시지 처리 핸들러 |
| Non-Blocking Retry | 별도 토픽으로 재시도하여 메인 처리 방해 없음 |
| KafkaListenerEndpointRegistry | 리스너 동적 제어 |

---

## 설정 예시

```yaml
spring:
  kafka:
    consumer:
      group-id: telemetry-consumer
      auto-offset-reset: earliest
      enable-auto-commit: false
    listener:
      type: batch
      ack-mode: manual
```

```kotlin
@RetryableTopic(
    attempts = "5",
    backoff = Backoff(delay = 5000, multiplier = 2.0),
    dltStrategy = DltStrategy.FAIL_ON_ERROR,
    dltTopicSuffix = ".dlt",
    retryTopicSuffix = ".retry",
    exclude = [NonRetryableException::class]
)
@KafkaListener(topics = ["telemetry.event"], groupId = "telemetry-consumer")
fun consume(records: List<ConsumerRecord<String, String>>, ack: Acknowledgment) {
    try {
        bulkInsert(records)
        ack.acknowledge()
    } catch (e: RetryableException) {
        throw e  // 재시도 대상
    }
}

@DltHandler
fun processDltMessage(record: ConsumerRecord<String, String>) {
    alertService.sendAlert("DLT 메시지 발생", record)
    dlqRepository.save(record)
}
```

---

## 아키텍처 다이어그램

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│   Producer   │────▶│  Main Topic  │────▶│   Consumer   │
└──────────────┘     └──────────────┘     └──────┬───────┘
                                                  │
                            실패 시               │
                     ┌────────────────────────────┘
                     │
                     ▼
              ┌──────────────┐
              │ Retry Topics │ ← 5회 재시도 (지수 백오프)
              │ .retry-0 ~ 3 │
              └──────┬───────┘
                     │
              모두 실패 시
                     │
                     ▼
              ┌──────────────┐     ┌──────────────┐
              │     DLT      │────▶│  PostgreSQL  │
              │  .dlt Topic  │     │   DLQ 테이블  │
              └──────────────┘     └──────────────┘
                                          │
                                   SQL 조회/분석
                                   선택적 재처리
                                          │
                                          ▼
                                   ┌──────────────┐
                                   │  Main Topic  │ ← 재발행
                                   │  (재처리)     │
                                   └──────────────┘
```

---

## 기술 선택과 Trade-off

### 왜 Kafka DLT를 선택했는가?

**고려한 대안들:**

| 방식 | 장점 | 단점 |
|------|------|------|
| **예외 무시** | 단순함 | 데이터 유실, 원인 파악 불가 |
| **무한 재시도** | 데이터 유실 없음 | Consumer 블로킹, 장애 전파 |
| **별도 DB 저장** | SQL 조회 용이 | 인프라 추가, 일관성 관리 |
| **Kafka DLT** | 메시지 보존, 비차단 | 재처리 불편, 조회 어려움 |

**Kafka DLT를 선택한 이유:**
1. 기존 Kafka 인프라 활용 (추가 비용 없음)
2. 메인 Consumer 블로킹 없음
3. Spring Kafka의 `@RetryableTopic` 지원

### 하이브리드(DLT + DB)를 선택한 이유

**Kafka DLT만 사용 시 한계:**
```
운영자: "어제 실패한 메시지 중 device_id가 ABC인 것만 재처리해주세요"
개발자: "... Kafka에서 그걸 찾으려면 전체 메시지를 consume해야 합니다"
```

**Trade-off:**

| 기준 | DLT Only | DLT + DB |
|------|----------|----------|
| 구현 복잡도 | 낮음 | 중간 |
| 조회/분석 | 어려움 | SQL로 즉시 |
| 선택적 재처리 | 불편 | 쉬움 |
| 저장 비용 | 낮음 | DB 비용 추가 |
| 일관성 관리 | 단순 | 이중 저장 관리 |

**결론:** 운영 편의성이 구현 복잡도를 압도. 실패 메시지 분석 시간이 **분 단위에서 초 단위**로 단축되었다.

### @RetryableTopic vs SeekToCurrentErrorHandler

Spring Kafka에서 재시도 전략 선택:

| 전략 | 방식 | 적합한 상황 |
|------|------|-------------|
| **SeekToCurrentErrorHandler** | 같은 파티션에서 재시도 | 순서 보장 필요, 간단한 재시도 |
| **@RetryableTopic** | 별도 retry 토픽 생성 | 비차단 재시도, 긴 백오프 |

**@RetryableTopic 선택 이유:**
- 재시도 중에도 다른 메시지 처리 가능 (Non-blocking)
- 지수 백오프로 긴 대기 시간 가능
- DLT 자동 생성

**Trade-off:**
- 메시지 순서 보장 안 됨 (순서가 중요하면 SeekToCurrentErrorHandler)
- 토픽 수 증가 (retry-0, retry-1, ... , dlt)

### 지수 백오프 설정 Trade-off

```kotlin
backoff = Backoff(delay = 5000, multiplier = 2.0, maxDelay = 300000)
// 5초 → 10초 → 20초 → 40초 → 80초 (최대 5분)
```

**짧은 초기 지연 (5초):**
- 장점: 일시적 오류 빠르게 복구
- 단점: 외부 서비스 부하

**긴 초기 지연 (30초):**
- 장점: 외부 서비스 복구 시간 확보
- 단점: 복구 지연

**우리의 선택:** 5초 시작, 2배 증가. 대부분의 일시적 오류는 첫 재시도에서 해결되고, 장기 장애는 지수 증가로 대응한다.

### 재처리 API 설계 Trade-off

**동기 재처리:**
```kotlin
// 즉시 결과 반환
POST /api/dlq/{id}/reprocess → 200 OK / 500 Error
```
- 장점: 결과 즉시 확인
- 단점: 대량 재처리 시 타임아웃

**비동기 재처리 (선택):**
```kotlin
// 작업 ID 반환 후 비동기 처리
POST /api/dlq/batch-reprocess → 202 Accepted { "jobId": "abc" }
GET /api/dlq/jobs/{jobId} → { "status": "IN_PROGRESS", "processed": 150, "total": 500 }
```
- 장점: 대량 처리 가능, 진행 상황 추적
- 단점: 구현 복잡도

---

## 블로그 링크

- [Kafka Consumer 재시도와 Dead Letter Topic 전략](https://gyeom.github.io/dev-notes/posts/2023-12-11-kafka-dlt-strategy/)
- [DLQ 재처리 전략: Kafka DLT, PostgreSQL DLQ, 그리고 하이브리드](https://gyeom.github.io/dev-notes/posts/2025-09-15-dlq-retry-strategy-kafka-postgresql/)

---

*다음: [04-outbox-pattern.md](./04-outbox-pattern.md)*
