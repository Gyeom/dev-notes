---
title: "Kafka 대용량 메시지 처리: Batch Listener와 Bulk Insert 전략"
date: 2023-12-08
draft: false
tags: ["Kafka", "Spring Kafka", "Batch Processing", "Bulk Insert", "성능 최적화"]
categories: ["Kafka"]
summary: "1분마다 50만 건의 메시지를 처리하는 Telemetry 서비스 개선 사례. Kafka Batch Listener, Spring JDBC Bulk Insert, Async 처리를 조합한 대용량 데이터 처리 전략"
---

## 문제 상황

Telemetry 서비스는 1분마다 각 장비의 모니터링 메시지를 수신하여 파싱하고 저장하는 역할을 수행한다. 초기에는 메시지를 개별적으로 처리하고 데이터베이스에 건별로 삽입하는 방식을 사용했다.

![AS-IS 아키텍처](/dev-notes/images/kafka/telemetry-as-is.png)

이 접근법은 단순하고 직관적이지만, 데이터 양이 급격히 증가하면서 문제가 발생했다.

**개별 처리 방식의 한계**

1. **네트워크 오버헤드**: 각 메시지마다 DB 통신 발생
2. **트랜잭션 비용**: 메시지당 트랜잭션 시작/커밋
3. **Connection Pool 고갈**: 동시 처리 시 커넥션 부족
4. **처리량 한계**: 메시지 양 증가에 선형적으로 느려짐

---

## 개선 전략 개요

세 가지 전략을 조합하여 대용량 데이터 처리 아키텍처로 전환했다.

| 전략 | 목적 | 효과 |
|------|------|------|
| Kafka Batch Listener | 메시지 묶음 처리 | 네트워크 오버헤드 감소 |
| Bulk Insert | DB 쓰기 최적화 | 트랜잭션 비용 절감 |
| Concurrency + @Async | 병렬 처리 | 처리량 증가 |

![TO-BE 아키텍처](/dev-notes/images/kafka/telemetry-to-be.png)

---

## 전략 1: Kafka Batch Listener

### Batch Listener란?

일반적인 Kafka Listener가 메시지를 개별적으로 처리하는 것과 달리, Batch Listener는 여러 메시지를 한 번에 처리한다. [Spring Kafka 공식 문서](https://docs.spring.io/spring-kafka/reference/kafka/receiving-messages/message-listener-container.html)에 따르면, Batch 모드는 "배치 전체를 처리하는 경우"에 성능 향상을 제공한다.

> Batch mode will improve performance if you are processing the batch as a whole - e.g. a batch insert using JDBC in a single transaction.

### Container Factory 설정

```kotlin
@Bean
fun batchKafkaListenerContainerFactory(): ConcurrentKafkaListenerContainerFactory<String, String> {
    val factory = ConcurrentKafkaListenerContainerFactory<String, String>()
    factory.consumerFactory = batchConsumerFactory()
    factory.isBatchListener = true

    factory.containerProperties.apply {
        ackMode = ContainerProperties.AckMode.MANUAL_IMMEDIATE
        idleBetweenPolls = 60000  // poll 사이 대기 시간
    }

    return factory
}
```

**핵심 설정**

| 설정 | 역할 |
|------|------|
| `setBatchListener(true)` | 배치 모드 활성화 |
| `AckMode.MANUAL_IMMEDIATE` | 수동 커밋으로 정확한 오프셋 관리 |
| `idleBetweenPolls` | poll 사이 대기 시간으로 메시지 축적 |

### Consumer 설정

```kotlin
@Bean
fun batchConsumerFactory(): ConsumerFactory<String, String> {
    val props = mapOf(
        ConsumerConfig.BOOTSTRAP_SERVERS_CONFIG to bootstrapServers,
        ConsumerConfig.GROUP_ID_CONFIG to groupId,
        ConsumerConfig.AUTO_OFFSET_RESET_CONFIG to "earliest",

        // 배치 크기 제어
        ConsumerConfig.MAX_POLL_RECORDS_CONFIG to 500,
        ConsumerConfig.FETCH_MIN_BYTES_CONFIG to 500000,
        ConsumerConfig.FETCH_MAX_WAIT_MS_CONFIG to 3000,

        // 타임아웃 설정
        ConsumerConfig.MAX_POLL_INTERVAL_MS_CONFIG to 300000,
        ConsumerConfig.SESSION_TIMEOUT_MS_CONFIG to 15000,
        ConsumerConfig.HEARTBEAT_INTERVAL_MS_CONFIG to 5000,
    )
    return DefaultKafkaConsumerFactory(props)
}
```

**주요 Consumer Config 옵션**

| 옵션 | 설명 |
|------|------|
| `max.poll.records` | 한 번의 poll()에서 가져올 최대 레코드 수 |
| `fetch.min.bytes` | 브로커가 반환하기 전에 모아야 할 최소 데이터 양 |
| `fetch.max.wait.ms` | fetch.min.bytes에 도달하기 위해 대기하는 최대 시간 |
| `max.poll.interval.ms` | poll() 호출 간 최대 허용 시간 |

> **주의**: `fetch.max.wait.ms`는 반드시 `max.poll.interval.ms`보다 작아야 한다. 그렇지 않으면 브로커가 Consumer를 비정상으로 판단하여 Rebalancing이 발생한다.

### Batch Listener 구현

```kotlin
@KafkaListener(
    topics = ["telemetry.1min.batch.v1"],
    containerFactory = "batchKafkaListenerContainerFactory"
)
fun consume(records: List<ConsumerRecord<String, String>>, ack: Acknowledgment) {
    try {
        val parsedData = records.map { parser.parse(it.value()) }
        repository.saveAll(parsedData)
        ack.acknowledge()
    } catch (e: Exception) {
        // 에러 처리
        throw e
    }
}
```

---

## 전략 2: Bulk Insert

### Spring JDBC의 batchUpdate

개별 INSERT 대신 Bulk Insert를 사용하면 DB 쓰기 성능이 크게 향상된다. [Spring 공식 문서](https://docs.spring.io/spring-framework/reference/data-access/jdbc/advanced.html)에서는 "대부분의 JDBC 드라이버는 동일한 prepared statement에 대한 배치 호출 시 성능이 향상된다"고 설명한다.

```kotlin
fun saveAll(bulkData: List<TelemetryData>): IntArray {
    val batch = SqlParameterSourceUtils.createBatch(bulkData.toTypedArray())
    return namedParameterJdbcTemplate.batchUpdate(SQL_INSERT, batch)
}
```

### 성능 최적화 포인트

**1. JDBC URL 설정**

PostgreSQL의 경우 `reWriteBatchedInserts=true` 옵션을 추가하면 배치 INSERT가 단일 multi-value statement로 변환된다.

```yaml
spring:
  datasource:
    url: jdbc:postgresql://localhost:5432/db?reWriteBatchedInserts=true
```

MySQL에서는 다음 옵션을 권장한다.

```yaml
spring:
  datasource:
    url: jdbc:mysql://localhost:3306/db?rewriteBatchedStatements=true&cachePrepStmts=true&useServerPrepStmts=true
```

**2. 적정 배치 크기**

배치 크기는 100~500개가 적절하다. 너무 작으면 오버헤드 감소 효과가 적고, 너무 크면 메모리 압박이 발생한다.

**3. 인덱스 영향**

대상 테이블의 인덱스가 많을수록 성능이 저하된다. 각 행 삽입 시 인덱스 조정이 필요하기 때문이다.

---

## 전략 3: Concurrency와 @Async

### 파티션 증가의 부작용

Kafka에서 처리량을 늘리는 일반적인 방법은 파티션 수를 늘리는 것이다. 하지만 이 접근법에는 부작용이 있다.

| 문제 | 설명 |
|------|------|
| 브로커 메모리 증가 | 각 파티션의 메타데이터를 메모리에 저장 |
| 리밸런싱 오버헤드 | 파티션이 많을수록 리더 선출/리밸런싱 빈번 |
| 복제 지연 | 복제할 데이터 양 증가 |
| 장애 복구 시간 증가 | 복구할 데이터 양 증가 |

### 애플리케이션 레벨 스케일링

파티션 수를 늘리는 대신, 애플리케이션 레벨에서 동시성을 확보한다.

**Concurrency 설정**

```kotlin
@Bean
fun batchKafkaListenerContainerFactory(): ConcurrentKafkaListenerContainerFactory<String, String> {
    val factory = ConcurrentKafkaListenerContainerFactory<String, String>()
    factory.setConcurrency(2)  // Consumer 스레드 수
    // ...
    return factory
}
```

**Async 설정**

```kotlin
@Configuration
@EnableAsync
class AsyncConfig {

    @Bean("batchExecutor")
    fun batchExecutor(): Executor {
        return ThreadPoolTaskExecutor().apply {
            corePoolSize = 3
            maxPoolSize = 8
            queueCapacity = 20
            keepAliveSeconds = 120
            setRejectedExecutionHandler(ThreadPoolExecutor.CallerRunsPolicy())
            setThreadNamePrefix("Async-Batch-")
            initialize()
        }
    }

    @Bean("parserExecutor")
    fun parserExecutor(): Executor {
        return ThreadPoolTaskExecutor().apply {
            corePoolSize = 3
            maxPoolSize = 8
            queueCapacity = 20
            keepAliveSeconds = 120
            setRejectedExecutionHandler(ThreadPoolExecutor.CallerRunsPolicy())
            setThreadNamePrefix("Async-Parser-")
            initialize()
        }
    }
}
```

**Async 적용**

```kotlin
@Async("batchExecutor")
@Transactional
fun saveAllAsync(bulkData: List<TelemetryData>) {
    repository.saveAll(bulkData)
}
```

> **CallerRunsPolicy**: 큐가 가득 찼을 때 호출자 스레드에서 직접 실행한다. 백프레셔 효과로 시스템 과부하를 방지한다.

---

## 결과

### 부하 테스트 환경

| 구성 요소 | 사양 |
|----------|------|
| Kafka Broker | kafka.m5.2xlarge, 2개 |
| K8S Deployment | 4 Pod (CPU 6 cores, Memory 6000Mi limit) |
| TimescaleDB | m5.4xlarge Access Node + 2 Data Node |

### 목표 달성

- **1분마다 50만 건** 메시지 처리 (하루 누적 7억 2천 건)
- 메시지 크기: 약 5KB

---

## 정리

대용량 Kafka 메시지 처리를 위한 세 가지 전략을 조합했다.

| 전략 | 적용 위치 | 효과 |
|------|----------|------|
| Batch Listener | Consumer | 네트워크 오버헤드 감소, 트랜잭션 단위 확대 |
| Bulk Insert | Repository | DB 쓰기 성능 향상 |
| Async + Concurrency | Service | 병렬 처리로 처리량 증가 |

**핵심 원칙**

1. **Batch Listener**는 개별 처리가 아닌 "배치 전체 처리"에서 효과가 있다
2. **Bulk Insert**는 JDBC 드라이버 설정(`reWriteBatchedInserts`)과 함께 사용해야 최대 효과
3. **파티션 증가** 대신 애플리케이션 레벨 동시성으로 Kafka 인프라 복잡도를 낮춘다

---

## 참고 자료

- [Spring Kafka - Message Listener Container](https://docs.spring.io/spring-kafka/reference/kafka/receiving-messages/message-listener-container.html)
- [Spring JDBC Batch Operations](https://docs.spring.io/spring-framework/reference/data-access/jdbc/advanced.html)
- [Baeldung - Spring JDBC Batch Inserts](https://www.baeldung.com/spring-jdbc-batch-inserts)
- [Baeldung - Consuming Messages in Batch in Kafka](https://www.baeldung.com/kafka-kafkalistener-annotation-handle-messages-batch)
