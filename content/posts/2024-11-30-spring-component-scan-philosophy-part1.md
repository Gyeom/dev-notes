---
title: "Spring 의존성 주입, 보이게 관리하기 (1) - @SpringBootApplication을 버린 이유"
date: 2024-11-30
draft: false
tags: ["Spring", "Spring Boot", "Hexagonal Architecture", "Component Scan", "아키텍처"]
categories: ["Spring"]
summary: "@SpringBootApplication 대신 @EnableAutoConfiguration + @Import 패턴을 사용하는 이유와 Hexagonal Architecture에서의 명시적 의존성 관리"
series: ["Spring 의존성 주입, 보이게 관리하기"]
series_order: 1
---

## 시리즈

1. **@SpringBootApplication을 버린 이유** (현재 글)
2. [하나의 코드베이스, 세 개의 앱](/dev-notes/posts/2024-11-30-spring-component-scan-philosophy-part2/)
3. [Spring 통합 테스트, 빠르고 정확하게](/dev-notes/posts/2024-11-30-spring-component-scan-philosophy-part3/)

---

## 들어가며

"이 서비스가 어떤 빈을 주입받는지 알려면 어디를 봐야 하나요?"

Spring Boot 프로젝트에서 자주 듣는 질문이다. `@SpringBootApplication`은 편리하지만, 프로젝트가 커지면 어떤 컴포넌트가 어디서 등록되는지 파악하기 어려워진다. 이 글에서는 `@ComponentScan`의 암묵적 동작을 걷어내고, 의존성을 명시적으로 드러내는 방법을 다룬다.

---

## @SpringBootApplication의 문제

대부분의 Spring Boot 프로젝트는 이렇게 시작한다.

```kotlin
@SpringBootApplication
class MyApplication

fun main(args: Array<String>) {
    runApplication<MyApplication>(*args)
}
```

`@SpringBootApplication`은 세 가지 어노테이션의 조합이다.

```kotlin
@SpringBootConfiguration  // @Configuration 포함
@EnableAutoConfiguration  // 자동 설정
@ComponentScan           // 패키지 전체 스캔
```

문제는 `@ComponentScan`이다. 애플리케이션 클래스가 위치한 패키지와 그 하위 패키지를 **전부** 스캔한다.

### 암묵적 의존성의 위험

```
com.example/
├── MyApplication.kt        # @SpringBootApplication
├── controller/
│   └── UserController.kt   # @RestController - 자동 등록
├── service/
│   └── UserService.kt      # @Service - 자동 등록
├── repository/
│   └── UserRepository.kt   # @Repository - 자동 등록
└── config/
    └── SecurityConfig.kt   # @Configuration - 자동 등록
```

모든 빈이 "알아서" 등록된다. 편리하지만 위험하다.

**문제 1: 의존성이 보이지 않는다**

`MyApplication.kt`만 보면 이 애플리케이션이 어떤 컴포넌트로 구성되는지 알 수 없다. 실제로 어떤 빈이 등록되는지 확인하려면 모든 패키지를 뒤져야 한다.

**문제 2: 원치 않는 빈이 등록된다**

테스트용 클래스에 `@Component`를 붙이면 프로덕션에서도 등록된다. 특정 환경에서만 필요한 빈도 항상 등록된다.

**문제 3: 멀티 모듈에서 혼란**

```
project/
├── app-api/           # API 서버
├── app-consumer/      # Kafka 컨슈머
├── adapter-web/       # HTTP 어댑터
├── adapter-persistence/  # DB 어댑터
└── domain/            # 도메인 로직
```

`app-api`와 `app-consumer`가 같은 어댑터 모듈을 의존하면, 어떤 어댑터가 어느 앱에서 활성화되는지 파악하기 어렵다.

---

## 해결: @EnableAutoConfiguration + @Import

Hexagonal Architecture를 적용한 프로젝트에서는 다른 접근을 한다.

```kotlin
@EnableAutoConfiguration
@Import(
    WebAdapterConfig::class,
    PersistenceAdapterConfig::class,
    ClientAdapterConfig::class,
    CacheAdapterConfig::class,
    ProducerAdapterConfig::class,
    UseCaseConfig::class,
)
class VehiclePlatformApiApplication

fun main(args: Array<String>) {
    TimeZone.setDefault(TimeZone.getTimeZone("UTC"))
    runApplication<VehiclePlatformApiApplication>(*args)
}
```

### 핵심 차이

| 항목 | @SpringBootApplication | @EnableAutoConfiguration + @Import |
|------|------------------------|-----------------------------------|
| 빈 등록 | 암묵적 (패키지 스캔) | 명시적 (Config 클래스) |
| 의존성 파악 | 전체 코드 탐색 필요 | Application 클래스만 보면 됨 |
| 빈 제어 | 어려움 | Config 단위로 On/Off |
| 멀티 앱 | 복잡 | 앱별 Config 조합 |

`@EnableAutoConfiguration`은 Spring Boot의 자동 설정(DataSource, JPA, Kafka 등)을 유지한다. `@Import`로 우리가 만든 Config 클래스만 명시적으로 등록한다.

---

## 어댑터별 Config 클래스

### Inbound Adapter: WebAdapterConfig

HTTP 요청을 처리하는 컴포넌트를 등록한다.

```kotlin
@Configuration
@ComponentScan(
    basePackages = ["sirius.vplat.adapter.inbound.web"]
)
@ConfigurationPropertiesScan(
    basePackages = ["sirius.vplat.adapter.inbound.web.config"]
)
class WebAdapterConfig
```

이 Config가 Import되면 `sirius.vplat.adapter.inbound.web` 패키지의 컴포넌트만 스캔한다.

**등록되는 컴포넌트:**
- `@RestController`: DeviceController, VehicleController, MetadataController
- `@Component`: CorrelationIdFilter, ServiceAuthenticationFilter, ApiAuditFilter
- `@ControllerAdvice`: DefaultExceptionHandler

### Outbound Adapter: PersistenceAdapterConfig

데이터베이스 접근을 담당한다.

```kotlin
@Configuration
@ComponentScan(
    basePackages = ["sirius.vplat.adapter.outbound.persistence"]
)
@EnableJpaRepositories(
    basePackages = ["sirius.vplat.adapter.outbound.persistence"]
)
@EntityScan(
    basePackages = ["sirius.vplat.adapter.outbound.persistence"]
)
class PersistenceAdapterConfig
```

**등록되는 컴포넌트:**
- `@Repository`: Spring Data JPA 인터페이스
- `@Entity`: JPA 엔티티
- `@Adapter`: Port 구현체 (VehicleOutAdapter, DevicePersistenceAdapter)

### Outbound Adapter: ClientAdapterConfig

외부 API 호출을 담당한다.

```kotlin
@Configuration
@EnableFeignClients(
    basePackages = ["sirius.vplat.adapter.outbound.client"]
)
@ComponentScan(
    basePackages = ["sirius.vplat.adapter.outbound.client"]
)
class ClientAdapterConfig {

    @Bean
    fun feignLoggerLevel(): Logger.Level = Logger.Level.FULL

    @Bean
    fun feignRequestOptions(): Request.Options = Request.Options(
        Duration.ofMillis(5000),   // connect timeout
        Duration.ofMillis(10000),  // read timeout
        true
    )

    @Bean
    fun feignRetryer(): Retryer = Retryer.Default(
        1000L,  // initial interval
        3000L,  // max interval
        3       // max attempts
    )
}
```

**등록되는 컴포넌트:**
- `@FeignClient`: VdpServiceAdapter, VdpDeviceManagementClient
- `@Component`: Adapter 클래스들

Config 클래스에 Feign 공통 설정(타임아웃, 재시도)도 함께 정의한다.

### Outbound Adapter: ProducerAdapterConfig

Kafka 이벤트 발행을 담당한다.

```kotlin
@Configuration
@ComponentScan(
    basePackages = ["sirius.vplat.adapter.outbound.producer"]
)
class ProducerAdapterConfig
```

**등록되는 컴포넌트:**
- `KafkaEventAdapter`: 실제 Kafka 발행
- `NoOpEventAdapter`: 이벤트 발행 비활성 시 사용 (Null Object 패턴)

### Outbound Adapter: CacheAdapterConfig

Redis 캐싱을 담당한다.

```kotlin
@Configuration
@ComponentScan(
    basePackages = ["sirius.vplat.adapter.outbound.cache"]
)
class CacheAdapterConfig {

    @Bean
    fun redisTemplate(
        connectionFactory: RedisConnectionFactory
    ): RedisTemplate<String, Any> {
        val template = RedisTemplate<String, Any>()
        template.connectionFactory = connectionFactory
        template.keySerializer = StringRedisSerializer()
        template.valueSerializer = JdkSerializationRedisSerializer()
        return template
    }
}
```

RedisTemplate 빈을 명시적으로 등록하고 Serializer를 커스터마이징한다.

---

## UseCase: Bean 메서드로 명시적 등록

UseCase 클래스는 `@Service` 어노테이션을 붙이지 않는다. 대신 Config에서 `@Bean` 메서드로 등록한다.

```kotlin
@Configuration
@EnableAspectJAutoProxy
class UseCaseConfig {

    @Bean
    fun apiDeviceService(
        deviceOut: DeviceOut,
        deviceModelOut: DeviceModelOut,
        @Qualifier("vdpServiceAdapter") vdpOut: VdpOut,
        vehicleOut: VehicleOut,
        eventOut: EventOut,
        vehicleBrandOut: VehicleBrandOut,
        vehicleModelOut: VehicleModelOut,
        vehicleCategoryOut: VehicleCategoryOut,
        vehicleClassOut: VehicleClassOut
    ): DeviceUseCase = DeviceService(
        deviceOut,
        deviceModelOut,
        vdpOut,
        vehicleOut,
        eventOut,
        vehicleBrandOut,
        vehicleModelOut,
        vehicleCategoryOut,
        vehicleClassOut
    )

    @Bean
    fun vehicleService(
        vehicleContainerOut: VehicleContainerOut,
        vehicleOut: VehicleOut,
        deviceOut: DeviceOut,
        eventOut: EventOut
    ): VehicleUseCase = VehicleService(
        vehicleContainerOut,
        vehicleOut,
        deviceOut,
        eventOut
    )

    @Bean
    fun metadataService(
        vehicleBrandOut: VehicleBrandOut,
        vehicleModelOut: VehicleModelOut,
        vehicleCategoryOut: VehicleCategoryOut,
        vehicleClassOut: VehicleClassOut,
        deviceModelOut: DeviceModelOut
    ): MetadataUseCase = MetadataService(
        vehicleBrandOut,
        vehicleModelOut,
        vehicleCategoryOut,
        vehicleClassOut,
        deviceModelOut
    )
}
```

### 왜 @Service를 쓰지 않는가?

**1. 의존성이 명시적으로 드러난다**

`DeviceService`가 9개의 Port를 의존한다는 사실이 코드에서 바로 보인다. `@Service`를 쓰면 생성자를 열어봐야 알 수 있다.

**2. 같은 인터페이스의 여러 구현체를 다룰 수 있다**

```kotlin
@Bean
fun apiDeviceService(
    @Qualifier("vdpServiceAdapter") vdpOut: VdpOut,  // 실제 VDP API
    // ...
): DeviceUseCase = DeviceService(...)

@Bean(name = ["virtualVehicleEventUseCase"])
fun virtualVehicleEventService(
    @Qualifier("virtualVdpServiceAdapter") vdpOut: VdpOut,  // Virtual VDP
    // ...
): VehicleEventUseCase = VirtualVehicleEventService(...)
```

`VdpOut` 인터페이스에 두 가지 구현체가 있다.
- `vdpServiceAdapter`: 실제 VDP 시스템 호출
- `virtualVdpServiceAdapter`: 테스트/개발용 가상 구현

`@Qualifier`로 어떤 구현체를 주입할지 명시한다. `@Service`와 `@Autowired`만으로는 이런 제어가 어렵다.

**3. 앱별로 다른 UseCase를 등록할 수 있다**

API 앱의 UseCaseConfig:
```kotlin
@Bean
fun apiDeviceService(...): DeviceUseCase
@Bean
fun vehicleService(...): VehicleUseCase
@Bean
fun metadataService(...): MetadataUseCase
```

Consumer 앱의 UseCaseConfig:
```kotlin
@Bean
fun vehicleEventService(...): VehicleEventUseCase
// deviceService, metadataService는 없음
```

같은 UseCase 클래스를 공유하지만, 앱별로 필요한 것만 등록한다.

---

## 빈 등록 방식 정리

| 방식 | Config 클래스 | 등록 방법 | 사용 사례 |
|------|--------------|----------|----------|
| **Component Scan** | WebAdapterConfig | `@RestController`, `@Component` | 컨트롤러, 필터 |
| | PersistenceAdapterConfig | `@Repository`, `@Entity`, `@Adapter` | JPA 레포지토리 |
| | ClientAdapterConfig | `@FeignClient`, `@Component` | Feign 클라이언트 |
| | ProducerAdapterConfig | `@Component` | Kafka 어댑터 |
| | CacheAdapterConfig | `@Component` + Bean 메서드 | Redis 캐시 |
| **Bean 메서드** | UseCaseConfig | `@Bean` 메서드 | UseCase 구현체 |
| | KafkaProducerConfig | `@Bean` 메서드 | Kafka 템플릿 |

**어댑터**는 Component Scan으로 자동 등록한다. 어댑터 내부 구현은 프레임워크에 가깝고, 한 번 만들면 잘 바뀌지 않는다.

**UseCase**는 Bean 메서드로 명시적 등록한다. 비즈니스 로직의 핵심이고, 의존성을 명확히 파악해야 한다.

---

## 정리

`@SpringBootApplication`은 간편하지만 의존성이 숨는다. Hexagonal Architecture에서는 `@EnableAutoConfiguration` + `@Import` 패턴으로 의존성을 명시적으로 관리한다.

**핵심 원칙:**
1. Application 클래스만 보면 전체 구성을 파악할 수 있어야 한다
2. 어댑터는 Config 단위로 On/Off 할 수 있어야 한다
3. UseCase의 의존성은 코드에서 바로 보여야 한다

다음 글에서는 이 패턴이 멀티앱 환경에서 어떻게 활용되는지 다룬다.

---

**다음 글:** [하나의 코드베이스, 세 개의 앱](/dev-notes/posts/2024-11-30-spring-component-scan-philosophy-part2/)
