---
title: "Kafka Consumer 재시도와 Dead Letter Topic 전략"
date: 2023-12-11
draft: false
tags: ["Kafka", "Spring Kafka", "DLT", "Dead Letter Topic", "RetryableTopic", "에러 핸들링"]
categories: ["Kafka"]
summary: "Spring Kafka의 @RetryableTopic을 활용한 재시도 전략과 Dead Letter Topic 구현. 분산 환경에서 리스너를 동적으로 제어하는 방법까지"
---

## Dead Letter Topic이란?

분산 시스템에서 메시지 처리 실패는 흔한 일이다. 일시적인 네트워크 지연, 외부 API 오류, 데이터 형식 불일치 등 다양한 이유로 실패가 발생한다. 이러한 실패를 효과적으로 관리하기 위해 Dead Letter Topic(DLT)과 재시도 전략이 필요하다.

DLT는 재시도에도 불구하고 처리에 실패한 메시지를 저장하는 Kafka 토픽이다. '마지막 피난처'로서 다음 역할을 수행한다.

- 처리 실패 메시지의 안전한 격리
- 실패 원인 분석 및 디버깅
- 메인 데이터 스트림의 방해 최소화

---

## @RetryableTopic으로 재시도 구현

Spring Kafka 2.7.0부터 `@RetryableTopic` 어노테이션으로 non-blocking 재시도를 선언적으로 구현할 수 있다. [Spring Kafka 공식 문서](https://docs.spring.io/spring-kafka/reference/retrytopic/dlt-strategies.html)에서 상세 설정을 확인할 수 있다.

### 기본 구현

```kotlin
@RetryableTopic(
    attempts = "5",
    backoff = Backoff(delay = 5000, multiplier = 2.0),
    dltStrategy = DltStrategy.FAIL_ON_ERROR,
    dltTopicSuffix = ".dlt",
    retryTopicSuffix = ".retry",
    exclude = [NonRetryableException::class]
)
@KafkaListener(
    topics = ["order.created"],
    groupId = "order-service",
    containerFactory = "kafkaListenerContainerFactory"
)
fun consume(record: ConsumerRecord<String, String>) {
    try {
        val order = objectMapper.readValue(record.value(), Order::class.java)
        orderService.process(order)
    } catch (e: RetryableException) {
        log.error("Retryable error: ${e.message}")
        throw e  // 재시도 대상
    } catch (e: NonRetryableException) {
        log.error("Non-retryable error: ${e.message}")
        throw e  // 즉시 DLT로 이동
    }
}
```

### 주요 설정 옵션

| 옵션 | 설명 |
|------|------|
| `attempts` | 최대 시도 횟수 (첫 시도 포함) |
| `backoff.delay` | 재시도 간 대기 시간 (ms) |
| `backoff.multiplier` | 대기 시간 증가율 |
| `dltStrategy` | DLT 처리 실패 시 동작 |
| `exclude` | 재시도하지 않을 예외 클래스 |

### 재시도 흐름

`attempts = 5`, `delay = 5000`, `multiplier = 2.0` 설정 시:

```
1차 시도 → 실패 → order.created.retry-0 (5초 후)
2차 시도 → 실패 → order.created.retry-1 (10초 후)
3차 시도 → 실패 → order.created.retry-2 (20초 후)
4차 시도 → 실패 → order.created.retry-3 (40초 후)
5차 시도 → 실패 → order.created.dlt
```

---

## DLT 처리 전략

### @DltHandler로 DLT 메시지 처리

```kotlin
@DltHandler
fun processDltMessage(
    record: ConsumerRecord<String, String>,
    @Header(KafkaHeaders.RECEIVED_TOPIC) topic: String,
    @Header(KafkaHeaders.RECEIVED_PARTITION) partition: Int,
    @Header(KafkaHeaders.OFFSET) offset: Long,
    @Header(KafkaHeaders.EXCEPTION_MESSAGE) errorMessage: String
) {
    log.error("""
        DLT 메시지 수신
        - Topic: $topic
        - Partition: $partition
        - Offset: $offset
        - Error: $errorMessage
        - Value: ${record.value()}
    """.trimIndent())

    // 알림 발송, DB 저장 등
    alertService.sendDltAlert(topic, errorMessage)
    dltRepository.save(DltRecord(topic, partition, offset, record.value(), errorMessage))
}
```

### DLT 처리 실패 전략

DLT 처리 자체가 실패할 경우 두 가지 옵션이 있다.

| 전략 | 동작 | 사용 시점 |
|------|------|----------|
| `ALWAYS_RETRY_ON_ERROR` | DLT로 다시 전송 (기본값) | 일시적 오류가 예상될 때 |
| `FAIL_ON_ERROR` | 처리 중단 | DLT 처리가 반드시 성공해야 할 때 |

```kotlin
@RetryableTopic(
    dltProcessingFailureStrategy = DltStrategy.FAIL_ON_ERROR
)
```

### DLT 없이 운영하기

특정 상황에서는 DLT 없이 재시도만 수행할 수 있다.

```kotlin
@RetryableTopic(
    dltProcessingFailureStrategy = DltStrategy.NO_DLT
)
```

---

## 분산 환경에서 리스너 동적 제어

DLT에 쌓인 메시지를 분석하고 코드를 수정한 후, 리스너를 재시작하여 재처리해야 할 때가 있다. 분산 환경에서는 여러 인스턴스가 동시에 운영되므로, Kafka 토픽을 통해 리스너를 제어하는 방식이 효과적이다.

### 제어 API 구현

```kotlin
@RestController
@RequestMapping("/v1/kafka")
class KafkaControlController(
    private val kafkaControlService: KafkaControlService
) {
    @PostMapping("/control")
    fun control(@RequestBody request: ListenerControlRequest): ResponseEntity<String> {
        return try {
            kafkaControlService.broadcastControl(request)
            ResponseEntity.ok("Control message sent")
        } catch (e: Exception) {
            log.error("Error sending control message", e)
            ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body("Error: ${e.message}")
        }
    }
}

data class ListenerControlRequest(
    val listenerId: String,
    val action: ListenerAction  // START, STOP
)

enum class ListenerAction { START, STOP }
```

### 제어 메시지 브로드캐스트

모든 파티션에 제어 메시지를 발행하여 모든 인스턴스가 수신하도록 한다.

```kotlin
@Service
class KafkaControlService(
    private val kafkaTemplate: KafkaTemplate<String, String>,
    private val objectMapper: ObjectMapper
) {
    fun broadcastControl(request: ListenerControlRequest) {
        val topic = "kafka.control"
        val partitions = kafkaTemplate.partitionsFor(topic)

        partitions.forEach { partition ->
            val message = objectMapper.writeValueAsString(request)
            val record = ProducerRecord(topic, partition.partition(), null, message)
            kafkaTemplate.send(record)
            log.info("Control message sent to partition ${partition.partition()}")
        }
    }
}
```

### 리스너 동적 제어

`KafkaListenerEndpointRegistry`를 사용하여 리스너를 시작/중지한다.

```kotlin
@Component
class KafkaListenerController(
    private val registry: KafkaListenerEndpointRegistry
) {
    @KafkaListener(topics = ["kafka.control"], groupId = "control-group")
    fun handleControlMessage(record: ConsumerRecord<String, String>) {
        val request = objectMapper.readValue(record.value(), ListenerControlRequest::class.java)

        val container = registry.getListenerContainer(request.listenerId)
            ?: throw IllegalArgumentException("Listener not found: ${request.listenerId}")

        when (request.action) {
            ListenerAction.START -> {
                container.start()
                log.info("Listener started: ${request.listenerId}")
            }
            ListenerAction.STOP -> {
                container.stop()
                log.info("Listener stopped: ${request.listenerId}")
            }
        }
    }
}
```

### 사용 시나리오

```bash
# DLT 리스너 중지 (코드 수정 배포 중)
curl -X POST http://api-server/v1/kafka/control \
  -H "Content-Type: application/json" \
  -d '{"listenerId": "order-dlt-listener", "action": "STOP"}'

# 배포 완료 후 DLT 리스너 재시작
curl -X POST http://api-server/v1/kafka/control \
  -H "Content-Type: application/json" \
  -d '{"listenerId": "order-dlt-listener", "action": "START"}'
```

---

## 예외 분류 전략

재시도할 예외와 즉시 DLT로 보낼 예외를 명확히 구분해야 한다.

### Retryable 예외

일시적이며 재시도로 해결될 가능성이 있는 예외:

- 네트워크 타임아웃
- 외부 API 일시 장애
- 데이터베이스 연결 실패
- 리소스 부족 (Rate Limit)

### Non-Retryable 예외

재시도해도 해결되지 않는 예외:

- 메시지 역직렬화 실패 (`DeserializationException`)
- 데이터 유효성 검증 실패
- 비즈니스 로직 오류
- 메시지 형식 불일치 (`MessageConversionException`)

```kotlin
@RetryableTopic(
    exclude = [
        DeserializationException::class,
        MessageConversionException::class,
        ValidationException::class,
        BusinessRuleViolationException::class
    ]
)
```

> Spring Kafka는 `DeserializationException`, `MessageConversionException`, `ConversionException`을 기본적으로 fatal 예외로 처리하여 `ALWAYS_RETRY_ON_ERROR`에서도 재시도하지 않는다.

---

## DLT 자동 시작 제어

DLT 핸들러를 수동으로 시작하도록 설정할 수 있다.

```kotlin
@RetryableTopic(
    autoStartDltHandler = false
)
```

이후 `KafkaListenerEndpointRegistry`로 필요할 때 시작한다.

```kotlin
@EventListener(ApplicationReadyEvent::class)
fun onApplicationReady() {
    if (shouldStartDltHandler()) {
        registry.getListenerContainer("order-dlt-handler")?.start()
    }
}
```

---

## 정리

Kafka 메시지 처리 실패 관리를 위한 전략을 정리한다.

| 구성 요소 | 역할 |
|----------|------|
| `@RetryableTopic` | 선언적 재시도 설정 |
| `@DltHandler` | DLT 메시지 처리 |
| `DltStrategy` | DLT 처리 실패 시 동작 결정 |
| `KafkaListenerEndpointRegistry` | 리스너 동적 제어 |

**핵심 원칙**

1. **예외 분류**: Retryable vs Non-Retryable 명확히 구분
2. **Backoff 전략**: 지수 백오프로 시스템 부하 방지
3. **DLT 모니터링**: 알림 및 로깅으로 빠른 대응
4. **동적 제어**: 분산 환경에서 Kafka 토픽을 통한 리스너 제어

---

## 참고 자료

- [Spring Kafka - DLT Strategies](https://docs.spring.io/spring-kafka/reference/retrytopic/dlt-strategies.html)
- [Baeldung - Dead Letter Queue for Kafka With Spring](https://www.baeldung.com/kafka-spring-dead-letter-queue)
- [Baeldung - Implementing Retry in Kafka Consumer](https://www.baeldung.com/spring-retry-kafka-consumer)
- [Spring Kafka Non-Blocking Retries and Dead Letter Topics](https://github.com/eugene-khyst/spring-kafka-non-blocking-retries-and-dlt)
