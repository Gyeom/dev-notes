---
title: "@SpringBootApplication을 버리고 얻은 것들"
date: 2024-11-30
draft: false
tags: ["Spring", "Kotlin", "Architecture", "Hexagonal"]
categories: ["Architecture"]
summary: "컴포넌트 스캔을 명시적으로 제어하면 헥사고날 아키텍처의 진정한 이점을 누릴 수 있다"
---

## 문제: @SpringBootApplication의 마법

Spring Boot를 시작하면 가장 먼저 배우는 것이 `@SpringBootApplication`이다.

```kotlin
@SpringBootApplication
class MyApplication

fun main(args: Array<String>) {
    runApplication<MyApplication>(*args)
}
```

이 한 줄이면 모든 게 동작한다. 편리하다. 하지만 이 편리함에는 대가가 있다.

`@SpringBootApplication`은 세 가지 애너테이션의 조합이다.

```kotlin
@SpringBootConfiguration
@EnableAutoConfiguration
@ComponentScan  // ← 문제의 시작
class MyApplication
```

`@ComponentScan`은 해당 패키지와 그 하위의 모든 `@Component`, `@Service`, `@Repository`, `@Controller`를 찾아서 빈으로 등록한다. 개발자가 클래스에 애너테이션만 붙이면 스프링이 알아서 찾아준다.

처음에는 편하다. 프로젝트가 커지면 문제가 시작된다.

## 암묵적 의존성의 늪

```
src/main/kotlin/
├── controller/
│   └── VehicleController.kt      // @RestController
├── service/
│   └── VehicleService.kt         // @Service
├── repository/
│   └── VehicleRepository.kt      // @Repository
├── client/
│   └── ExternalApiClient.kt      // @Component
└── scheduler/
    └── BatchScheduler.kt         // @Component + @Scheduled
```

이 구조에서 `@SpringBootApplication`을 쓰면 모든 빈이 등록된다. 문제는 이게 의도인지 실수인지 알 수 없다는 것이다.

- `BatchScheduler`가 정말 이 앱에서 실행되어야 하나?
- `ExternalApiClient`가 테스트 환경에서도 등록되어야 하나?
- 새로 추가한 `@Component`가 어떤 앱에 영향을 주는지 파악하려면?

코드 리뷰에서 "이 클래스가 어떤 앱에서 쓰이나요?"라는 질문에 답하려면 프로젝트 전체를 뒤져야 한다.

## 해결: 명시적 Import로 전환

```kotlin
@EnableAutoConfiguration
@Import(
    WebAdapterConfig::class,
    PersistenceAdapterConfig::class,
    CacheAdapterConfig::class,
    ClientAdapterConfig::class,
    ProducerAdapterConfig::class,
    UseCaseConfig::class,
)
class VehiclePlatformApiApplication
```

`@SpringBootApplication` 대신 `@EnableAutoConfiguration`과 `@Import`를 사용한다. 차이점은 명확하다.

| 방식 | 빈 등록 | 의도 파악 |
|------|---------|----------|
| `@SpringBootApplication` | 자동 (패키지 스캔) | 전체 코드 검색 필요 |
| `@EnableAutoConfiguration` + `@Import` | 명시적 (선언된 것만) | Application 클래스만 보면 됨 |

이제 Application 클래스만 보면 이 앱이 무엇으로 구성되어 있는지 한눈에 파악된다.

## 각 어댑터가 자신의 경계를 책임진다

Import되는 Config 클래스들은 각자의 패키지만 스캔한다.

```kotlin
// Web 어댑터 - REST API 관련만 스캔
@Configuration
@ComponentScan(basePackages = ["sirius.vplat.adapter.inbound.web"])
class WebAdapterConfig

// Persistence 어댑터 - DB 관련만 스캔
@Configuration
@ComponentScan(basePackages = ["sirius.vplat.adapter.outbound.persistence"])
@EnableJpaRepositories(basePackages = ["sirius.vplat.adapter.outbound.persistence"])
@EntityScan(basePackages = ["sirius.vplat.adapter.outbound.persistence"])
class PersistenceAdapterConfig

// Cache 어댑터 - Redis 관련만 스캔
@Configuration
@ComponentScan(basePackages = ["sirius.vplat.adapter.outbound.cache"])
class CacheAdapterConfig
```

각 Config가 자신의 영역에서 필요한 설정을 모두 처리한다. `PersistenceAdapterConfig`는 JPA Repository와 Entity 스캔까지 책임진다. 필요한 곳에서만 Import한다.

## 같은 도메인, 다른 앱

이 방식의 진짜 가치는 하나의 도메인 로직으로 여러 앱을 만들 때 드러난다.

### API Application

```kotlin
@EnableAutoConfiguration
@Import(
    WebAdapterConfig::class,           // REST API
    PersistenceAdapterConfig::class,   // DB
    CacheAdapterConfig::class,         // Redis 캐시
    ClientAdapterConfig::class,        // 외부 API 호출
    ProducerAdapterConfig::class,      // Kafka 발행
    UseCaseConfig::class,              // 비즈니스 로직
)
class VehiclePlatformApiApplication
```

### Consumer Application

```kotlin
@EnableAutoConfiguration
@Import(
    VehicleConsumerAdapterConfig::class,  // Kafka Consumer
    PersistenceAdapterConfig::class,      // DB
    ClientAdapterConfig::class,           // 외부 API 호출
    ProducerAdapterConfig::class,         // 이벤트 재발행
    SlackAdapterConfig::class,            // 에러 알림
    UseCaseConfig::class,                 // 비즈니스 로직
)
class VehiclePlatformConsumerApplication
```

### Outbox Application

```kotlin
@EnableAutoConfiguration
@Import(
    OutboxSchedulerAdapterConfig::class,  // 스케줄러
    PersistenceAdapterConfig::class,      // DB (Outbox 테이블)
    SlackAdapterConfig::class,            // 에러 알림
    OutboxKafkaConfig::class,             // Kafka 발행
)
class OutboxApplication
```

세 앱이 같은 `PersistenceAdapterConfig`를 공유하지만, 나머지 구성은 각자의 역할에 맞게 다르다.

- API 앱: REST + 캐시 + 외부 API
- Consumer 앱: Kafka 소비 + 외부 API + 알림
- Outbox 앱: 스케줄러 + DB + Kafka 발행

`@SpringBootApplication`으로는 이런 구성이 불가능하다. 모든 빈이 등록되거나, 아예 등록되지 않거나 둘 중 하나다.

## UseCase는 왜 @Service를 안 쓰나

Application 모듈의 서비스 클래스에는 `@Service`가 없다.

```kotlin
// vp-application 모듈
class DeviceService(
    private val deviceOut: DeviceOut,
    private val deviceModelOut: DeviceModelOut,
    private val vdpOut: VdpOut,
    // ...
) : DeviceUseCase {
    override fun createDevice(command: CreateDeviceCommand): Device {
        // 비즈니스 로직
    }
}
```

대신 각 앱의 `UseCaseConfig`에서 수동으로 빈을 등록한다.

```kotlin
// API 앱의 UseCaseConfig
@Configuration
class UseCaseConfig {
    @Bean
    fun apiDeviceService(
        deviceOut: DeviceOut,
        deviceModelOut: DeviceModelOut,
        @Qualifier("vdpServiceAdapter") vdpOut: VdpOut,
        // ...
    ): DeviceUseCase = DeviceService(
        deviceOut, deviceModelOut, vdpOut, // ...
    )
}
```

이 방식에는 세 가지 이유가 있다.

### 1. 앱마다 다른 의존성 주입

같은 `DeviceService`지만 API 앱과 Consumer 앱에서 다른 구현체를 주입한다.

```kotlin
// API 앱 - 실제 VDP 연동
@Qualifier("vdpServiceAdapter") vdpOut: VdpOut

// 테스트용 앱 - Mock VDP
@Qualifier("virtualVdpServiceAdapter") vdpOut: VdpOut
```

`@Service`를 쓰면 이런 유연성이 사라진다. 빈 이름이 고정되고, 주입 대상도 고정된다.

### 2. 앱마다 필요한 UseCase만 등록

```kotlin
// API 앱 - 모든 UseCase
@Bean fun deviceService(...): DeviceUseCase
@Bean fun vehicleService(...): VehicleUseCase
@Bean fun metadataService(...): MetadataUseCase

// Consumer 앱 - 이벤트 처리만
@Bean fun vehicleEventService(...): VehicleEventUseCase
```

Consumer 앱에 `MetadataUseCase`는 필요 없다. `@Service`를 쓰면 모든 서비스가 등록되고, 사용하지 않는 빈이 메모리를 차지한다.

### 3. 순환 참조 명시적 제어

수동 빈 등록은 의존성 그래프를 코드로 표현한다. 순환 참조가 발생하면 컴파일 단계에서 바로 드러난다.

```kotlin
@Bean
fun serviceA(serviceB: ServiceB): ServiceA = ServiceA(serviceB)

@Bean
fun serviceB(serviceA: ServiceA): ServiceB = ServiceB(serviceA)  // 컴파일 시점에 순환 감지
```

## 설정 파일도 조합한다

빈 구성만 명시적인 게 아니다. `application.yml`도 같은 철학을 따른다.

### 앱별로 필요한 설정만 include

```yaml
# API Application
spring:
  application:
    name: vp-core-api-app
  profiles:
    active: api
    include: datasource, auth, logging, kafka, redis, client

# Consumer Application
spring:
  application:
    name: vp-core-consumer-app
  profiles:
    active: consumer
    include: datasource, auth, logging, kafka, client  # redis 없음

# Outbox Application
spring:
  application:
    name: vp-core-outbox-app
  profiles:
    active: outbox
    include: datasource, auth, logging, kafka  # client, redis 없음
```

API 앱은 Redis가 필요하지만, Outbox 앱은 필요 없다. `profiles.include`로 필요한 설정 파일만 조합한다.

### 설정 파일의 위치: 앱 vs 어댑터

설정 파일은 두 곳에 위치한다.

**앱 모듈** - 앱마다 달라지는 설정:
```
vp-core-api-app/src/main/resources/
├── application.yml
├── application-datasource.yml   # API 앱의 DB 설정 (pool-size: 30)
├── application-kafka.yml        # API 앱의 Kafka 설정
└── application-redis.yml        # API 앱만 Redis 사용

vp-core-consumer-app/src/main/resources/
├── application.yml
├── application-datasource.yml   # Consumer 앱의 DB 설정 (pool-size: 20)
└── application-kafka.yml        # Consumer 앱의 Kafka 설정
```

앱마다 connection pool 크기, Kafka consumer group 등이 다르다. 이런 설정은 앱 모듈에 둔다.

**어댑터 모듈** - 어댑터 고유의 공통 설정:
```
vp-adapter/outbound/client/src/main/resources/
└── application-client.yml       # 외부 API URL, timeout 등
```

외부 API URL이나 Feign 클라이언트 설정은 어떤 앱에서 쓰든 동일하다. 이런 설정은 어댑터 모듈에 둔다.

`application-client.yml`은 외부 API 연동에 필요한 공통 설정을 담고 있다.

```yaml
# application-client.yml (vp-adapter/outbound/client 모듈)
external:
  api:
    vdp:
      url: https://vdp-connect-api.int.42dot.io
      timeout:
        connect: 5000
        read: 10000
      use-inmemory: false

feign:
  client:
    config:
      default:
        connectTimeout: 5000
        readTimeout: 10000
        loggerLevel: FULL

---
spring.config.activate.on-profile: perf

external:
  api:
    vdp:
      use-inmemory: true  # 성능 테스트 시 실제 API 호출 건너뛰기
```

이 파일이 `client` 어댑터와 함께 움직인다. 앱에서 `ClientAdapterConfig`를 Import하면, 자연스럽게 `application-client.yml`도 필요하다는 걸 알 수 있다.

### 환경별 오버라이드도 명확하다

각 설정 파일 내에서 프로파일별 오버라이드를 관리한다.

```yaml
# application-datasource.yml
spring:
  datasource:
    url: jdbc:postgresql://localhost:5432/vplat_int  # 기본값
    hikari:
      maximum-pool-size: 10

---
spring.config.activate.on-profile: int

spring:
  datasource:
    url: jdbc:postgresql://common-int-main.rds.amazonaws.com/vplat_int
    hikari:
      maximum-pool-size: 30

---
spring.config.activate.on-profile: real

spring:
  datasource:
    url: ${DATABASE_URL}
    hikari:
      maximum-pool-size: 30
      connection-timeout: 3000  # 운영 환경은 빠른 실패
```

DB 관련 설정은 `application-datasource.yml` 한 파일에서 모든 환경을 관리한다. 다른 설정 파일과 섞이지 않아서 찾기 쉽다.

## 테스트에서의 이점

### 어댑터 레벨 통합 테스트

각 어댑터를 독립적으로 테스트한다. Application 클래스와 동일한 패턴으로 필요한 Config만 Import한다.

```kotlin
@EnableAutoConfiguration
@ContextConfiguration(initializers = [PersistenceTestConfig::class])
@Import(PersistenceAdapterConfig::class)  // Persistence 어댑터만 로드
class DeviceRepositoryAdapterTest(
    private val deviceRepositoryAdapter: DeviceRepositoryAdapter
) : DescribeSpec({

    describe("DeviceRepositoryAdapter") {
        it("단말을 저장하고 조회한다") {
            val device = createTestDevice()
            deviceRepositoryAdapter.save(device)

            val found = deviceRepositoryAdapter.findById(device.id)
            found shouldBe device
        }
    }
})
```

이 테스트는 PostgreSQL 컨테이너만 띄운다. Kafka, Redis, 외부 API 연동 없이 순수하게 DB 어댑터만 검증한다.

### 테스트 컨테이너도 어댑터별로 분리

```kotlin
// Persistence 테스트용 - PostgreSQL만
class PersistenceTestConfig : ApplicationContextInitializer<ConfigurableApplicationContext> {
    companion object {
        private val postgres = PostgreSQLContainer("postgres:15-alpine")
            .withDatabaseName("vplat_test")
            .apply { start() }
    }

    override fun initialize(context: ConfigurableApplicationContext) {
        TestPropertyValues.of(
            "spring.datasource.url=${postgres.jdbcUrl}",
            "spring.datasource.username=${postgres.username}",
            "spring.datasource.password=${postgres.password}"
        ).applyTo(context.environment)
    }
}

// 전체 통합 테스트용 - PostgreSQL + Redis + Kafka
class TestContainerConfig : ApplicationContextInitializer<ConfigurableApplicationContext> {
    companion object {
        private val postgres = PostgreSQLContainer("postgres:15-alpine")
        private val redis = GenericContainer("redis:7-alpine")
        private val kafka = KafkaContainer(DockerImageName.parse("confluentinc/cp-kafka:7.4.0"))
        // ...
    }
}
```

어댑터 레벨 테스트는 `PersistenceTestConfig`로 빠르게 실행한다. E2E 테스트만 `TestContainerConfig`로 전체 인프라를 띄운다.

### Mock 어댑터로 외부 의존성 격리

전체 통합 테스트에서 외부 API 호출은 Mock으로 대체한다.

```kotlin
@TestConfiguration
class MockAdapterConfig {
    @Bean
    @Primary  // 실제 구현체 대신 이 Mock이 주입됨
    fun mockVdpServiceAdapter(): VdpServiceAdapter {
        return mockk<VdpServiceAdapter>().apply {
            every { registerDevice(any(), any(), any(), any(), any()) } returns
                VdpDeviceInfo(deviceId = UUID.randomUUID(), isActivated = true)
            every { deleteDevice(any()) } just Runs
        }
    }
}
```

`@Primary`로 선언하면 실제 `VdpServiceAdapter` 대신 Mock이 주입된다. 테스트 대상 앱의 Import 구조는 그대로 유지하면서, 외부 의존성만 교체한다.

```kotlin
@SpringBootTest
@Import(MockAdapterConfig::class)  // Mock 어댑터 추가
class DeviceIntegrationTest : BaseTestContainerSpec() {
    // 실제 앱과 동일한 구조로 테스트
    // VdpServiceAdapter만 Mock으로 동작
}
```

### 전체 통합 테스트 예시

실제 E2E 테스트는 이렇게 작성한다.

```kotlin
class DeviceIntegrationTest(
    mockMvc: MockMvc,
    databaseCleanup: DatabaseCleanup,
    private val objectMapper: ObjectMapper,
    private val deviceModelOut: DeviceModelOut,
    private val vehicleOut: VehicleOut,
) : BaseTestContainerSpec(mockMvc, databaseCleanup) {

    init {
        Given("단말 정보가 주어진 상태에서") {
            val deviceModel = createTestDeviceModel()
            deviceModelOut.save(deviceModel)

            val vehicle = createTestVehicle()
            vehicleOut.save(vehicle)

            val request = CreateDeviceRequest(
                vehicleId = vehicle.id.value,
                deviceSourceId = "device-source-001",
                deviceModelId = deviceModel.id.value
            )

            When("단말 생성 API를 호출하면") {
                Then("단말이 정상적으로 생성되어야 한다") {
                    mockMvc.post("/api/v1/devices") {
                        contentType = MediaType.APPLICATION_JSON
                        content = objectMapper.writeValueAsString(request)
                    }.andExpect {
                        status { isCreated() }
                        jsonPath("$.id") { exists() }
                    }
                }
            }
        }

        Given("생성된 단말이 있는 상태에서") {
            val deviceId = createTestDevice()

            When("단말 조회 API를 호출하면") {
                Then("단말 정보가 정상적으로 조회되어야 한다") {
                    mockMvc.get("/api/v1/devices/{id}", deviceId)
                        .andExpect {
                            status { isOk() }
                            jsonPath("$.id") { value(deviceId.toString()) }
                        }
                }
            }
        }
    }
}
```

이 테스트는 실제 앱과 동일한 빈 구성으로 실행된다. `BaseTestContainerSpec`이 PostgreSQL, Redis, Kafka 컨테이너를 띄우고, `MockAdapterConfig`가 외부 API 호출만 Mock으로 대체한다. 테스트 코드에서 앱의 아키텍처가 그대로 드러난다.

테스트 코드가 프로덕션 코드와 같은 구조를 따른다는 점이 이 방식의 장점이다. `@Import`로 필요한 어댑터를 조합하고, 테스트 전용 Config를 추가해서 외부 의존성을 제어한다.

### 테스트 인프라 컴포넌트

테스트를 지원하는 공통 컴포넌트들도 같은 철학을 따른다.

**BaseTestContainerSpec** - 전체 통합 테스트의 베이스 클래스다.

```kotlin
@SpringBootTest(
    webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
    classes = [VehiclePlatformApiApplication::class, TestConfig::class]
)
@ContextConfiguration(initializers = [TestContainerConfig::class])
@ActiveProfiles("integration")
@AutoConfigureMockMvc
abstract class BaseTestContainerSpec(
    protected val mockMvc: MockMvc,
    private val databaseCleanup: DatabaseCleanup
) : BehaviorSpec() {

    override fun isolationMode(): IsolationMode = IsolationMode.InstancePerLeaf

    init {
        beforeSpec {
            databaseCleanup.execute()
        }
    }
}
```

애너테이션들을 보면 프로덕션 Application 클래스(`VehiclePlatformApiApplication`)를 그대로 사용한다. 테스트용 Config(`TestConfig`)만 추가로 Import한다. 프로덕션과 테스트의 빈 구성이 일치하므로 테스트 결과를 신뢰할 수 있다.

**DatabaseCleanup** - 테스트 간 데이터 정리를 담당한다.

```kotlin
@Component
class DatabaseCleanup {
    @PersistenceContext
    private lateinit var entityManager: EntityManager

    @Transactional
    fun execute() {
        entityManager.flush()
        for (tableName in tableNames) {
            entityManager.createNativeQuery(
                "TRUNCATE TABLE vplat.$tableName RESTART IDENTITY CASCADE"
            ).executeUpdate()
        }
    }
}
```

`TestConfig`의 `@ComponentScan`에 의해 자동으로 빈 등록된다. 테스트 격리를 위해 각 테스트 전에 DB를 정리한다.

**TestConfig** - 테스트 전용 Config로 Mock 어댑터들을 스캔한다.

```kotlin
@Configuration
@ComponentScan(basePackages = ["sirius.vplat.test.config", "sirius.vplat.test.mock"])
class TestConfig {
    @Bean
    @Primary
    fun objectKafkaTemplate(...): KafkaTemplate<String, Any> {
        // 테스트용 Kafka 설정
    }
}
```

`sirius.vplat.test.mock` 패키지를 스캔해서 테스트용 Mock 어댑터들을 자동 등록한다.

**TestVdpServiceAdapter** - 테스트용 Mock 어댑터의 예시다.

```kotlin
@Component("vdpServiceAdapter")  // 실제 어댑터와 같은 빈 이름
@Primary                         // 실제 어댑터보다 우선
class TestVdpServiceAdapter : VdpOut {

    private val deviceStore = mutableMapOf<String, VdpDeviceInfo>()

    override fun registerDevice(
        deviceSourceId: String,
        // ...
    ): VdpDeviceInfo {
        // 메모리에 저장해서 테스트에서 검증 가능
        deviceStore[deviceSourceId]?.let { return it }

        val deviceInfo = VdpDeviceInfo(
            deviceId = UUID.randomUUID(),
            isActivated = true
        )
        deviceStore[deviceSourceId] = deviceInfo
        return deviceInfo
    }
}
```

`@Component("vdpServiceAdapter")`로 실제 어댑터와 같은 빈 이름을 사용하고, `@Primary`로 우선순위를 높인다. 테스트에서 외부 API 호출 없이 동작을 검증한다.

**VirtualVdpServiceAdapter** - 프로덕션에서도 사용하는 가상 어댑터다.

```kotlin
@Component("virtualVdpServiceAdapter")
@Profile("!integration")  // 통합 테스트 환경에서는 제외
class VirtualVdpServiceAdapter : VdpOut {
    override fun registerDevice(...): VdpDeviceInfo {
        // 실제 VDP 호출 없이 가상 디바이스 생성
        return VdpDeviceInfo(deviceId = UUID.randomUUID(), isActivated = true)
    }
}
```

가상 차량(VIN이 `:virtual`로 끝나는) 등록 시 실제 VDP 연동 없이 처리한다. `@Profile("!integration")`으로 통합 테스트에서는 `TestVdpServiceAdapter`가 대신 사용된다.

이처럼 같은 인터페이스(`VdpOut`)에 대해 여러 구현체를 상황에 맞게 선택한다. `@Qualifier`와 `@Profile`을 조합해서 프로덕션/테스트/가상 환경을 구분한다.

### 테스트 피라미드와 Import 패턴

| 테스트 레벨 | Import 범위 | 컨테이너 | 실행 시간 |
|------------|------------|----------|----------|
| 어댑터 단위 | `PersistenceAdapterConfig` | PostgreSQL만 | ~3초 |
| 서비스 통합 | 어댑터 + `UseCaseConfig` | PostgreSQL + Redis | ~5초 |
| E2E | 전체 앱 + `MockAdapterConfig` | 전체 | ~10초 |

`@SpringBootApplication`을 쓰면 모든 테스트가 전체 앱을 로드한다. Import 패턴은 테스트 범위에 맞는 최소한의 빈만 로드해서 테스트 실행 시간을 줄인다.

### 앱 시작 시간 단축

필요한 빈만 로드해서 앱 시작 시간을 단축한다. CI에서 수백 개의 테스트를 돌릴 때 효과가 크다. 프로덕션 앱도 마찬가지로 불필요한 빈을 로드하지 않는다. Outbox 앱은 Web 어댑터가 필요 없으니, 해당 빈들을 로드하지 않아서 더 빨리 시작한다.

## 정리

`@SpringBootApplication`의 컴포넌트 스캔은 편리하지만, 그 편리함이 아키텍처를 숨긴다.

| 관점 | @SpringBootApplication | @Import 방식 |
|------|------------------------|--------------|
| 빈 등록 | 암묵적 | 명시적 |
| 설정 파일 | 하나의 거대한 yml | 앱/어댑터별 분리된 yml |
| 앱 구성 파악 | 전체 코드 검색 | Application 클래스 확인 |
| 멀티 앱 구성 | 어려움 | 자연스러움 |
| 테스트 격리 | 어려움 | 쉬움 |
| 앱 시작 시간 | 모든 빈 로드 | 필요한 빈만 로드 |
| 새 개발자 온보딩 | "일단 다 올라감" | "이 앱은 이것들로 구성됨" |

핵심은 **명시성**이다. 빈 등록도, 설정 파일도, 앱 구성도 모두 코드에서 명시적으로 선언한다. 암묵적인 마법 대신 읽을 수 있는 구조를 선택한다.

헥사고날 아키텍처를 적용했다면, 컴포넌트 스캔과 설정 파일도 그 철학에 맞게 설계해야 한다. 어댑터는 교체 가능해야 하고, 앱은 필요한 어댑터만 조합해서 구성한다.

`@SpringBootApplication`은 시작점으로 좋다. 하지만 프로젝트가 성장하면, 명시적 제어로 전환하는 것을 고려해볼 만하다. 코드 몇 줄이 늘어나는 대신, 아키텍처가 코드에 드러난다.
