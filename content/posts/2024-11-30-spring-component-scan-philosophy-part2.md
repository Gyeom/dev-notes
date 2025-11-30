---
title: "Spring 컴포넌트 스캔의 철학 (2) - 멀티앱 설정 전략"
date: 2024-11-30
draft: false
tags: ["Spring", "Spring Boot", "Multi-Module", "Configuration", "profiles.include"]
categories: ["Spring"]
summary: "같은 코드베이스에서 API 서버, Kafka 컨슈머, 배치 앱을 profiles.include로 구성하는 방법"
series: ["Spring 컴포넌트 스캔의 철학"]
series_order: 2
---

## 시리즈

1. [Part 1: @SpringBootApplication을 버리다](/dev-notes/posts/2024-11-30-spring-component-scan-philosophy-part1/)
2. **Part 2: 멀티앱 설정 전략** (현재 글)
3. [Part 3: 테스트가 쉬워지는 구조](/dev-notes/posts/2024-11-30-spring-component-scan-philosophy-part3/)

---

## 멀티앱 아키텍처

하나의 코드베이스에서 여러 애플리케이션을 실행한다.

```
vplat-server/
├── vp-core-api-app/        # API 서버 (HTTP 요청 처리)
├── vp-core-consumer-app/   # Kafka 컨슈머 (메시지 수신)
├── vp-core-outbox-app/     # 아웃박스 처리 (이벤트 발행)
├── vp-adapter/
│   ├── inbound/
│   │   ├── web/            # HTTP 어댑터
│   │   ├── vehicle-consumer/  # Kafka 리스너
│   │   └── outbox-scheduler/  # 스케줄러
│   └── outbound/
│       ├── persistence/    # DB 접근
│       ├── client/         # 외부 API
│       ├── producer/       # Kafka 발행
│       ├── cache/          # Redis
│       └── slack/          # Slack 알림
├── vp-application/         # UseCase 구현
└── vp-domain/              # 도메인 모델
```

같은 도메인 로직을 공유하지만, 진입점이 다르다.

---

## 앱별 Import 구성

### API App

```kotlin
@EnableAutoConfiguration
@Import(
    WebAdapterConfig::class,           // HTTP 컨트롤러
    PersistenceAdapterConfig::class,   // DB
    ClientAdapterConfig::class,        // 외부 API (Feign)
    CacheAdapterConfig::class,         // Redis
    ProducerAdapterConfig::class,      // Kafka 발행
    UseCaseConfig::class,              // 비즈니스 로직
    KafkaProducerConfig::class,        // Kafka 설정
    ApplicationSupportConfig::class,   // AOP, 메트릭
    MetricsConfig::class               // Prometheus
)
class VehiclePlatformApiApplication
```

### Consumer App

```kotlin
@EnableAutoConfiguration
@Import(
    VehicleConsumerAdapterConfig::class,  // Kafka 리스너
    PersistenceAdapterConfig::class,      // DB
    ClientAdapterConfig::class,           // 외부 API
    SlackAdapterConfig::class,            // Slack 알림
    ProducerAdapterConfig::class,         // Kafka 발행 (이벤트 전파)
    UseCaseConfig::class,                 // 비즈니스 로직
    KafkaConsumerConfig::class,           // Kafka Consumer 설정
    ApplicationSupportConfig::class       // AOP
)
class VehiclePlatformConsumerApplication
```

### Outbox App

```kotlin
@EnableAutoConfiguration
@Import(
    OutboxSchedulerAdapterConfig::class,  // 스케줄러
    PersistenceAdapterConfig::class,      // DB (아웃박스 테이블)
    SlackAdapterConfig::class,            // 실패 알림
    ApplicationSupportConfig::class,      // AOP
    OutboxKafkaConfig::class              // Kafka 발행 설정
)
class OutboxApplication
```

### Import 비교

| Config | API | Consumer | Outbox |
|--------|-----|----------|--------|
| WebAdapterConfig | ✓ | | |
| VehicleConsumerAdapterConfig | | ✓ | |
| OutboxSchedulerAdapterConfig | | | ✓ |
| PersistenceAdapterConfig | ✓ | ✓ | ✓ |
| ClientAdapterConfig | ✓ | ✓ | |
| CacheAdapterConfig | ✓ | | |
| ProducerAdapterConfig | ✓ | ✓ | |
| SlackAdapterConfig | | ✓ | ✓ |
| UseCaseConfig | ✓ | ✓ | |

Application 클래스만 보면 각 앱이 어떤 어댑터를 사용하는지 파악된다.

---

## profiles.include로 설정 합성

각 앱은 필요한 설정 파일을 `profiles.include`로 조합한다.

### API App의 application.yml

```yaml
spring:
  application:
    name: vp-core-api-app
  profiles:
    active: api
    include: datasource, auth, logging, kafka, web-client, redis, client, vdp, http-client
```

9개의 설정 파일을 포함한다.

### Consumer App의 application.yml

```yaml
spring:
  application:
    name: vp-core-consumer-app
  profiles:
    active: consumer
    include: datasource, auth, logging, kafka, web-client, redis, client
```

7개의 설정 파일을 포함한다. `vdp`, `http-client`가 빠졌다.

### Outbox App의 application.yml

```yaml
spring:
  application:
    name: vp-core-outbox-app
  profiles:
    active: outbox
    include: datasource, auth, logging, kafka
```

4개의 설정 파일만 포함한다. 가장 단순한 구성이다.

### 포함 설정 비교

| 설정 파일 | API | Consumer | Outbox | 내용 |
|----------|-----|----------|--------|------|
| datasource | ✓ | ✓ | ✓ | PostgreSQL 연결 |
| auth | ✓ | ✓ | ✓ | 서비스 인증 |
| logging | ✓ | ✓ | ✓ | 로깅 레벨 |
| kafka | ✓ | ✓ | ✓ | Kafka 서버 |
| web-client | ✓ | ✓ | | WebClient 설정 |
| redis | ✓ | ✓ | | Redis 캐시 |
| client | ✓ | ✓ | | 외부 API URL |
| vdp | ✓ | | | VDP 시스템 설정 |
| http-client | ✓ | | | HTTP 타임아웃 |

---

## 설정 파일 위치 전략

### 앱 전용 설정 vs 공유 설정

설정 파일은 두 곳에 위치한다.

**앱 모듈 (vp-core-*-app/src/main/resources/)**
- `application.yml` - 앱별 기본 설정
- `application-datasource.yml` - DB 연결 (풀 사이즈가 앱마다 다름)
- `application-kafka.yml` - Kafka 설정 (Producer/Consumer 차이)

**어댑터 모듈 (vp-adapter/*/src/main/resources/)**
- `application-client.yml` - 외부 API URL (모든 앱이 동일)
- `application-logging.yml` - 로깅 설정 (공통)

### 왜 이렇게 나누는가?

**Connection Pool 사이즈**

API 앱과 Consumer 앱의 DB 부하가 다르다.

```yaml
# API App - application-datasource.yml
spring:
  datasource:
    hikari:
      maximum-pool-size: 30  # 동시 HTTP 요청 처리

# Consumer App - application-datasource.yml
spring:
  datasource:
    hikari:
      maximum-pool-size: 10  # Kafka 파티션 수에 맞춤
```

**Kafka 설정**

API 앱은 Producer, Consumer 앱은 Consumer 설정이 필요하다.

```yaml
# API App - application-kafka.yml
spring:
  kafka:
    platform:
      producer:
        acks: all
        retries: 2147483647
        enable-idempotence: true

# Consumer App - application-kafka.yml
spring:
  kafka:
    platform:
      consumer:
        group-id: vplat-server
        auto-offset-reset: earliest
        concurrency: 3
        enable-auto-commit: false
```

---

## 환경별 설정 오버라이드

각 설정 파일은 환경별로 값을 오버라이드한다.

### application-datasource.yml

```yaml
# Default (local)
spring:
  datasource:
    url: jdbc:postgresql://localhost:5432/vplat_int
    username: vplat_int
    password: ftdot42edoc
    hikari:
      maximum-pool-size: 10
  jpa:
    hibernate:
      ddl-auto: create

---
spring.config.activate.on-profile: int

spring:
  datasource:
    url: jdbc:postgresql://common-int-main.rds.amazonaws.com/vplat_int
    username: vplat_int
    password: ${POSTGRESQL_PASSWORD}
    hikari:
      maximum-pool-size: 30
  jpa:
    hibernate:
      ddl-auto: validate

---
spring.config.activate.on-profile: real

spring:
  datasource:
    url: ${DATABASE_URL}
    username: ${DATABASE_USERNAME}
    password: ${POSTGRESQL_PASSWORD}
    hikari:
      maximum-pool-size: 30
      connection-timeout: 3000
```

### 환경별 특징

| 환경 | DB URL | 자격증명 | Pool | DDL | 특징 |
|------|--------|---------|------|-----|------|
| local | localhost | 하드코딩 | 10 | create | 개발용 |
| int | AWS RDS | 환경변수 | 30 | validate | 통합 환경 |
| stage | AWS RDS | 환경변수 | 30 | validate | 스테이징 |
| real | 환경변수 | 환경변수 | 30 | validate | 프로덕션 |
| perf | AWS RDS | 하드코딩 | 30 | validate | 성능 테스트 |

**local**: 빠른 개발을 위해 스키마를 자동 생성한다.
**int/stage/real**: 스키마 변경은 마이그레이션으로만 한다. `validate`로 불일치 시 실패한다.
**real**: 민감 정보는 환경변수로만 주입한다.

---

## Kafka 환경별 설정

### 로컬 vs 운영

```yaml
# Default (local)
spring:
  kafka:
    platform:
      bootstrap-servers: localhost:9092
      producer:
        security:
          protocol: PLAINTEXT

---
spring.config.activate.on-profile: int

spring:
  kafka:
    platform:
      bootstrap-servers: b-1.common-int-main.kafka.amazonaws.com:9096,b-2.common-int-main.kafka.amazonaws.com:9096
      producer:
        security:
          protocol: SASL_SSL
          sasl:
            mechanism: SCRAM-SHA-512
            jaas:
              config: "org.apache.kafka.common.security.scram.ScramLoginModule required username=\"kafka\" password=\"${KAFKA_PASSWORD}\";"
```

로컬에서는 보안 없이 빠르게 개발한다. 운영 환경에서는 SASL_SSL로 인증과 암호화를 적용한다.

### Consumer Concurrency

```yaml
# Default (local)
spring:
  kafka:
    platform:
      consumer:
        concurrency: 3  # 빠른 처리

---
spring.config.activate.on-profile: stage

spring:
  kafka:
    platform:
      consumer:
        concurrency: 1  # 순서 보장

---
spring.config.activate.on-profile: real

spring:
  kafka:
    platform:
      consumer:
        concurrency: 1  # 순서 보장
```

로컬에서는 빠른 처리를 위해 동시성을 높인다. 운영에서는 메시지 순서 보장을 위해 1로 제한한다.

---

## 인증 설정 패턴

### 환경별 서비스 인증

```yaml
# Default (local)
service:
  auth:
    enabled: false
    service-id: hubble
    client-secret: change-me-in-production

---
spring.config.activate.on-profile: int

service:
  auth:
    enabled: true
    allowed-services:
      - service-id: hubble
        client-secret: ${SERVICE_CLIENT_SECRET}
      - service-id: test
        client-secret: ${TEST_CLIENT_SECRET:test-secret-int}

---
spring.config.activate.on-profile: real

service:
  auth:
    enabled: true
    allowed-services:
      - service-id: hubble
        client-secret: ${SERVICE_CLIENT_SECRET}
```

**local**: 인증 비활성. 개발 편의성 우선.
**int**: 인증 활성 + 테스트용 서비스 추가. 기본값 제공 (`test-secret-int`).
**real**: 인증 활성. 환경변수만 사용. 기본값 없음.

---

## 기능 플래그

### Kafka 이벤트 발행

```yaml
# Default (local)
kafka:
  enabled: false  # 로컬에서는 Kafka 없이 개발

---
spring.config.activate.on-profile: int

kafka:
  enabled: true

---
spring.config.activate.on-profile: perf

kafka:
  enabled: false  # 성능 테스트 시 이벤트 발행 제외
```

### 문서화 (SpringWolf)

```yaml
# Default
springwolf:
  enabled: true

---
spring.config.activate.on-profile: perf

springwolf:
  enabled: false  # 성능 테스트 시 문서화 비활성
```

성능 테스트에서는 불필요한 기능을 끄고 순수 API 성능만 측정한다.

---

## Outbox 앱 전용 설정

```yaml
outbox:
  processor:
    pending-check-interval-ms: 5000   # 대기 이벤트 확인 주기
    retry-check-interval-ms: 60000    # 재시도 확인 주기
    batch-size: 100                   # 배치 처리 크기
    max-retry-count: 5                # 최대 재시도 횟수
    cleanup-after-days: 7             # 완료 이벤트 보관 기간
    min-age-seconds: 10               # 최소 대기 시간

slack:
  bot:
    channel:
      outbox-error: ${SLACK_OUTBOX_ERROR_CHANNEL:#vplat-outbox-alerts}
  token: ${SLACK_BOT_TOKEN:}
  enabled: ${SLACK_ENABLED:false}
```

Outbox 앱만의 설정이다. 이벤트 처리 실패 시 Slack으로 알림을 보낸다.

---

## 앱 시작 시간

Import 패턴의 부가 효과로 앱 시작 시간이 줄어든다.

| 앱 | Import 수 | 설정 수 | 시작 시간 (예상) |
|----|----------|---------|-----------------|
| API | 9 | 9 | ~8초 |
| Consumer | 8 | 7 | ~6초 |
| Outbox | 5 | 4 | ~3초 |

필요한 컴포넌트만 로드하므로 불필요한 빈 생성 오버헤드가 없다.

---

## 정리

`profiles.include`로 설정을 모듈화하면 멀티앱 환경을 깔끔하게 관리할 수 있다.

**핵심 원칙:**
1. 앱 전용 설정과 공유 설정을 분리한다
2. 환경별 오버라이드는 같은 파일 내에서 `on-profile`로 처리한다
3. 민감 정보는 운영 환경에서만 환경변수로 주입한다
4. 기능 플래그로 환경별 동작을 제어한다

다음 글에서는 이 구조가 테스트를 어떻게 쉽게 만드는지 다룬다.

---

**다음 글:** [Part 3: 테스트가 쉬워지는 구조](/dev-notes/posts/2024-11-30-spring-component-scan-philosophy-part3/)
