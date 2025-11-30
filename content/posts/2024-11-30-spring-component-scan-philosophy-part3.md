---
title: "Spring 컴포넌트 스캔의 철학 (3) - 테스트가 쉬워지는 구조"
date: 2024-11-30
draft: false
tags: ["Spring", "Spring Boot", "Testing", "TestContainers", "Integration Test", "Kotest"]
categories: ["Spring"]
summary: "Import 패턴이 테스트를 어떻게 쉽게 만드는가. TestContainer, Mock 어댑터, 어댑터 레벨 테스트 전략"
series: ["Spring 컴포넌트 스캔의 철학"]
series_order: 3
---

## 시리즈

1. [Part 1: @SpringBootApplication을 버리다](/dev-notes/posts/2024-11-30-spring-component-scan-philosophy-part1/)
2. [Part 2: 멀티앱 설정 전략](/dev-notes/posts/2024-11-30-spring-component-scan-philosophy-part2/)
3. **Part 3: 테스트가 쉬워지는 구조** (현재 글)

---

## Import 패턴의 테스트 이점

`@SpringBootApplication`을 쓰면 모든 테스트가 전체 애플리케이션을 로드한다. Import 패턴을 쓰면 테스트 범위에 맞는 최소한의 컴포넌트만 로드한다.

| 테스트 레벨 | Import 범위 | 컨테이너 | 실행 시간 |
|------------|------------|----------|----------|
| 어댑터 단위 | `PersistenceAdapterConfig` | PostgreSQL만 | ~3초 |
| 서비스 통합 | 어댑터 + `UseCaseConfig` | PostgreSQL + Redis | ~5초 |
| E2E | 전체 앱 + `TestConfig` | 전체 | ~10초 |

---

## 테스트 디렉토리 구조

```
vp-core-api-app/
├── src/main/kotlin/...
└── src/integrationTest/
    ├── kotlin/sirius/vplat/
    │   ├── TestContainerConfig.kt        # 인프라 컨테이너
    │   ├── HealthCheckIntegrationTest.kt
    │   ├── DeviceIntegrationTest.kt
    │   ├── VehicleIntegrationTest.kt
    │   ├── support/
    │   │   └── BaseTestContainerSpec.kt  # 테스트 베이스 클래스
    │   └── test/
    │       ├── config/
    │       │   ├── TestConfig.kt         # 테스트용 Config
    │       │   └── DatabaseCleanup.kt    # DB 정리
    │       └── mock/
    │           ├── TestVdpServiceAdapter.kt      # Mock VDP
    │           └── TestVirtualVdpServiceAdapter.kt
    └── resources/
        ├── application.yml
        ├── application-datasource.yml
        └── ...
```

`integrationTest` 소스셋으로 통합 테스트를 분리한다.

---

## TestContainer 기반 인프라

### TestContainerConfig

```kotlin
class TestContainerConfig : ApplicationContextInitializer<ConfigurableApplicationContext> {

    companion object {
        private val postgres: PostgreSQLContainer<*> = PostgreSQLContainer("postgres:15-alpine")
            .withDatabaseName("vplat_int")
            .withUsername("test_user")
            .withPassword("test_password")
            .withInitScript("test-schema.sql")
            .apply { start() }

        private val redis: GenericContainer<*> = GenericContainer(
            DockerImageName.parse("redis:7-alpine")
        )
            .withExposedPorts(6379)
            .withCommand(
                "redis-server",
                "--appendonly", "yes",
                "--maxmemory", "256mb",
                "--maxmemory-policy", "allkeys-lru"
            )
            .apply { start() }

        private val kafka: KafkaContainer = KafkaContainer(
            DockerImageName.parse("confluentinc/cp-kafka:7.4.0")
        )
            .withKraft()
            .apply { start() }
    }

    override fun initialize(ctx: ConfigurableApplicationContext) {
        TestPropertyValues.of(
            "spring.datasource.url=${postgres.jdbcUrl}",
            "spring.datasource.username=${postgres.username}",
            "spring.datasource.password=${postgres.password}",
            "spring.data.redis.host=${redis.host}",
            "spring.data.redis.port=${redis.getMappedPort(6379)}",
            "spring.kafka.bootstrap-servers=${kafka.bootstrapServers}"
        ).applyTo(ctx)
    }
}
```

**구성:**
- **PostgreSQL 15**: 알파인 리눅스 (경량 이미지)
- **Redis 7**: LRU 정책, 256MB 제한
- **Kafka**: KRaft 모드 (Zookeeper 불필요)

**특징:**
- `companion object`로 싱글톤 유지. 여러 테스트 클래스가 같은 컨테이너를 공유한다.
- `withInitScript`로 테스트 스키마를 자동 생성한다.
- `ApplicationContextInitializer`로 Spring Context에 동적 프로퍼티를 주입한다.

---

## 테스트 베이스 클래스

### BaseTestContainerSpec

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

    override fun extensions() = listOf(SpringExtension)

    init {
        beforeSpec {
            databaseCleanup.execute()
        }
    }
}
```

**어노테이션 설명:**

| 어노테이션 | 설정 | 목적 |
|----------|------|------|
| `@SpringBootTest` | `RANDOM_PORT` | 포트 충돌 방지 |
| `@SpringBootTest` | `classes` | 앱 + TestConfig 로드 |
| `@ContextConfiguration` | `initializers` | TestContainer 적용 |
| `@ActiveProfiles` | `integration` | integration 프로필 |
| `@AutoConfigureMockMvc` | - | MockMvc 자동 설정 |

**Kotest 설정:**
- `BehaviorSpec`: Given/When/Then BDD 스타일
- `IsolationMode.InstancePerLeaf`: 각 테스트 케이스 격리
- `beforeSpec`: 테스트 시작 전 DB 정리

---

## 데이터베이스 정리

### DatabaseCleanup

```kotlin
@Component
class DatabaseCleanup {

    @PersistenceContext
    private lateinit var entityManager: EntityManager

    private val tableNames = mutableSetOf<String>()

    @Transactional
    fun execute() {
        if (tableNames.isEmpty()) {
            extractTableNames()
        }

        entityManager.flush()

        for (tableName in tableNames) {
            entityManager.createNativeQuery(
                "TRUNCATE TABLE vplat.$tableName RESTART IDENTITY CASCADE"
            ).executeUpdate()
        }
    }

    private fun extractTableNames() {
        val query = entityManager.createNativeQuery("""
            SELECT table_name
            FROM information_schema.tables
            WHERE table_schema = 'vplat'
            AND table_type = 'BASE TABLE'
        """)

        @Suppress("UNCHECKED_CAST")
        val result = query.resultList as List<String>
        tableNames.addAll(result)
    }
}
```

**동작:**
1. 첫 실행 시 `vplat` 스키마의 모든 테이블 이름 조회
2. 매 테스트 전 `TRUNCATE ... RESTART IDENTITY CASCADE` 실행
3. 테이블 캐싱으로 중복 조회 방지

**이점:**
- 테스트 간 데이터 격리 보장
- Auto Increment ID 초기화
- CASCADE로 FK 제약 조건 처리

---

## TestConfig

### 테스트 전용 Config

```kotlin
@Configuration
@ComponentScan(basePackages = ["sirius.vplat.test.config", "sirius.vplat.test.mock"])
class TestConfig {

    @Bean
    @Primary
    fun objectProducerFactory(
        @Value("\${spring.kafka.bootstrap-servers}") bootstrapServers: String
    ): ProducerFactory<String, Any> {
        val configs = mutableMapOf<String, Any>()
        configs[ProducerConfig.BOOTSTRAP_SERVERS_CONFIG] = bootstrapServers
        configs[ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG] = StringSerializer::class.java
        configs[ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG] = JsonSerializer::class.java
        configs[JsonSerializer.ADD_TYPE_INFO_HEADERS] = false
        return DefaultKafkaProducerFactory(configs)
    }

    @Bean
    @Primary
    fun objectKafkaTemplate(
        objectProducerFactory: ProducerFactory<String, Any>
    ): KafkaTemplate<String, Any> {
        return KafkaTemplate(objectProducerFactory)
    }
}
```

**역할:**
- `sirius.vplat.test.mock` 패키지의 Mock 어댑터 스캔
- TestContainer Kafka로 연결되는 KafkaTemplate 제공
- `@Primary`로 프로덕션 빈 오버라이드

---

## Mock 어댑터

### TestVdpServiceAdapter

```kotlin
@Component("vdpServiceAdapter")
@Primary
class TestVdpServiceAdapter : VdpOut {

    private val logger = LoggerFactory.getLogger(TestVdpServiceAdapter::class.java)
    private val deviceStore = mutableMapOf<String, VdpDeviceInfo>()

    override fun registerDevice(
        deviceSourceId: String,
        deviceMobileNumber: String?,
        vdpDeviceType: VdpDeviceType,
        vdpSourceIdType: VdpDeviceSourceIdType,
        hmgBrandType: String?
    ): VdpDeviceInfo {
        logger.info("Test mock: registerDevice - $deviceSourceId")

        // 이미 등록된 디바이스 반환
        deviceStore[deviceSourceId]?.let { return it }

        // 새 디바이스 생성
        val deviceInfo = VdpDeviceInfo(
            deviceId = UUID.randomUUID(),
            isActivated = true
        )
        deviceStore[deviceSourceId] = deviceInfo
        return deviceInfo
    }

    override fun removeDevice(deviceId: UUID) {
        logger.info("Test mock: removeDevice - $deviceId")
        deviceStore.entries.removeIf { it.value.deviceId == deviceId }
    }

    override fun activateDevice(deviceId: UUID) {
        logger.info("Test mock: activateDevice - $deviceId")
    }

    override fun deactivateDevice(deviceId: UUID) {
        logger.info("Test mock: deactivateDevice - $deviceId")
    }
}
```

**특징:**
- `@Component("vdpServiceAdapter")`: 프로덕션과 같은 빈 이름
- `@Primary`: 같은 이름의 빈이 있으면 이 빈이 우선
- 인메모리 저장소로 상태 유지
- 외부 VDP API 호출 없이 테스트 가능

### TestVirtualVdpServiceAdapter

```kotlin
@Component("virtualVdpServiceAdapter")
class TestVirtualVdpServiceAdapter : VdpOut {

    override fun registerDevice(
        deviceSourceId: String,
        deviceMobileNumber: String?,
        vdpDeviceType: VdpDeviceType,
        vdpSourceIdType: VdpDeviceSourceIdType,
        hmgBrandType: String?
    ): VdpDeviceInfo {
        return VdpDeviceInfo(
            deviceId = UUID.randomUUID(),
            isActivated = true
        )
    }

    // 다른 메서드들...
}
```

**차이:**
- 상태 저장 없음. 매번 새 UUID 생성
- Virtual Vehicle 시나리오 테스트용

### 빈 선택 메커니즘

```kotlin
// UseCaseConfig에서 Qualifier로 구분
@Bean
fun apiDeviceService(
    @Qualifier("vdpServiceAdapter") vdpOut: VdpOut,  // TestVdpServiceAdapter
    // ...
): DeviceUseCase

@Bean(name = ["virtualVehicleEventUseCase"])
fun virtualVehicleEventService(
    @Qualifier("virtualVdpServiceAdapter") vdpOut: VdpOut,  // TestVirtualVdpServiceAdapter
    // ...
): VehicleEventUseCase
```

프로덕션의 빈 등록 로직이 그대로 동작한다. Mock 어댑터만 바뀐다.

---

## 통합 테스트 예제

### DeviceIntegrationTest

```kotlin
class DeviceIntegrationTest(
    mockMvc: MockMvc,
    databaseCleanup: DatabaseCleanup,
    private val objectMapper: ObjectMapper,
    private val deviceModelOut: DeviceModelOut,
    private val vehicleOut: VehicleOut,
    private val vehicleContainerOut: VehicleContainerOut
) : BaseTestContainerSpec(mockMvc, databaseCleanup) {

    init {
        Given("단말 정보가 주어진 상태에서") {
            val deviceModelId = UUID.randomUUID()
            val deviceModel = DeviceModel(
                id = DeviceModelId(deviceModelId),
                deviceModelName = "Test Model",
                deviceType = "DOT42",
                manufactureCompany = "Test Company",
                deviceSourceIdType = "SERIAL_NO",
                devicePipeLineType = "DEFAULT",
                createdAt = OffsetDateTime.now(),
                updatedAt = OffsetDateTime.now()
            )
            deviceModelOut.save(deviceModel)

            val vehicleContainerId = VehicleContainerId.generate()
            val vehicleContainer = VehicleContainer(
                id = vehicleContainerId,
                spec = VehicleSpecification.create("KNAB1234567890123")
            )
            vehicleContainerOut.save(vehicleContainer)

            val vehicleId = VehicleId.generate()
            val vehicle = Vehicle(
                id = vehicleId,
                vehicleContainerId = vehicleContainerId,
                name = "Test Vehicle"
            )
            vehicleOut.save(vehicle)

            val request = CreateDeviceRequest(
                vehicleId = vehicleId.value,
                deviceSourceId = "device-source-001",
                deviceModelId = deviceModelId
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

        Given("존재하지 않는 단말 ID가 주어진 상태에서") {
            val nonExistentDeviceId = UUID.randomUUID().toString()

            When("단말 조회 API를 호출하면") {
                Then("404 오류가 반환되어야 한다") {
                    mockMvc.get("/api/v1/devices/{id}", nonExistentDeviceId) {
                        contentType = MediaType.APPLICATION_JSON
                    }.andExpect {
                        status { isNotFound() }
                    }
                }
            }
        }

        Given("중복된 deviceSourceId로 단말 생성 시") {
            val duplicateSourceId = "duplicate-device-001"
            createTestDevice("기존 단말", duplicateSourceId)

            When("동일한 deviceSourceId로 단말 생성 API를 호출하면") {
                Then("409 충돌 오류가 반환되어야 한다") {
                    // 새 차량, 새 디바이스 모델로 요청
                    val request = createDeviceRequest(duplicateSourceId)

                    mockMvc.post("/api/v1/devices") {
                        contentType = MediaType.APPLICATION_JSON
                        content = objectMapper.writeValueAsString(request)
                    }.andExpect {
                        status { isConflict() }
                    }
                }
            }
        }
    }

    private fun createTestDevice(name: String, deviceSourceId: String): UUID {
        // 테스트 데이터 생성 헬퍼
    }
}
```

**테스트 패턴:**
- Given: 사전 조건 설정 (DB에 테스트 데이터 삽입)
- When: API 호출
- Then: 응답 검증

**의존성 주입:**
- `mockMvc`: HTTP 요청/응답 처리
- `databaseCleanup`: 테스트 간 데이터 정리
- `deviceModelOut`, `vehicleOut`: 테스트 데이터 직접 삽입

---

## 어댑터 레벨 테스트

전체 앱을 로드하지 않고 어댑터만 테스트한다.

### PersistenceTestConfig

```kotlin
class PersistenceTestConfig : ApplicationContextInitializer<ConfigurableApplicationContext> {

    companion object {
        private val postgres: PostgreSQLContainer<*> = PostgreSQLContainer("postgres:15-alpine")
            .withDatabaseName("vplat_int")
            .withUsername("test_user")
            .withPassword("test_password")
            .apply { start() }
    }

    override fun initialize(ctx: ConfigurableApplicationContext) {
        TestPropertyValues.of(
            "spring.datasource.url=${postgres.jdbcUrl}",
            "spring.datasource.username=${postgres.username}",
            "spring.datasource.password=${postgres.password}",
            "spring.jpa.hibernate.ddl-auto=create-drop",
            "spring.jpa.show-sql=true"
        ).applyTo(ctx)
    }
}
```

**차이점:**
- `ddl-auto=create-drop`: 테스트 실행 시 스키마 생성, 종료 시 삭제
- PostgreSQL만 사용 (Redis, Kafka 없음)

### 어댑터 테스트 예제

```kotlin
@SpringBootTest(classes = [PersistenceAdapterConfig::class])
@ContextConfiguration(initializers = [PersistenceTestConfig::class])
class DevicePersistenceAdapterTest(
    private val deviceOut: DeviceOut
) : BehaviorSpec({

    Given("디바이스가 저장된 상태에서") {
        val device = Device(...)
        val savedDevice = deviceOut.save(device)

        When("ID로 조회하면") {
            val found = deviceOut.findById(savedDevice.id)

            Then("동일한 디바이스가 반환된다") {
                found shouldNotBe null
                found?.id shouldBe savedDevice.id
            }
        }
    }
})
```

**로드되는 컴포넌트:**
- `PersistenceAdapterConfig`만 Import
- JPA Repository, Entity, Adapter만 로드
- Controller, UseCase, 다른 어댑터는 로드하지 않음

---

## Consumer App 테스트

### MockAdapterConfig

```kotlin
@TestConfiguration
class MockAdapterConfig {

    @Bean
    @Primary
    fun mockVdpServiceAdapter(): VdpServiceAdapter {
        return mockk<VdpServiceAdapter>().apply {
            every { registerDevice(any(), any(), any(), any(), any()) } returns
                VdpDeviceInfo(deviceId = UUID.randomUUID(), isActivated = true)
            every { removeDevice(any()) } returns Unit
            every { activateDevice(any()) } returns Unit
            every { deactivateDevice(any()) } returns Unit
        }
    }
}
```

MockK를 사용해서 외부 API 클라이언트를 모킹한다.

### TestExternalConfig

```kotlin
@TestConfiguration
class TestExternalConfig {

    @Bean(name = ["vdpDeviceManagementClient"])
    @Primary
    fun mockVdpDeviceManagementClient(): VdpDeviceManagementClient {
        return mockk<VdpDeviceManagementClient>().apply {
            every { activateDevice(any()) } returns DeviceDetailCommonFeignResponse(
                deviceId = UUID.randomUUID()
            )
            every { retrieveDevices(any(), any(), any(), any(), any()) } returns VdpPageResponse(
                items = listOf(),
                pageInfo = VdpPageResponse.PageInfo(page = 0, size = 10, total = 0)
            )
            every { registerDevice(any()) } returns VdpRegisterDeviceOutput(
                deviceId = UUID.randomUUID()
            )
        }
    }

    @Bean(name = ["deviceApiClient"])
    @Primary
    fun mockDeviceApiClient(): DeviceApiClient {
        return mockk<DeviceApiClient>().apply {
            every { getDeviceHealth() } returns Unit
        }
    }
}
```

Feign 클라이언트를 MockK로 대체한다. 실제 외부 API 호출 없이 테스트한다.

---

## 테스트 설정 파일

### integrationTest/resources/application.yml

```yaml
server:
  port: 8080
  shutdown: graceful

spring:
  profiles:
    include: datasource, auth, kafka, web-client, logging, redis, test
  main:
    allow-bean-definition-overriding: true
```

`allow-bean-definition-overriding: true`로 Mock 빈이 프로덕션 빈을 오버라이드한다.

### application-test.yml

```yaml
# 테스트 특화 설정
service:
  auth:
    enabled: false  # 테스트에서 인증 비활성

logging:
  level:
    org.hibernate.SQL: DEBUG
    org.hibernate.type.descriptor.sql: TRACE
```

테스트 환경에서만 필요한 설정을 분리한다.

---

## 테스트 피라미드

```
        /\
       /  \     E2E (전체 앱)
      /    \    - BaseTestContainerSpec
     /------\   - 모든 컨테이너
    /        \
   /   통합   \  서비스 통합
  /    테스트  \ - 어댑터 + UseCase
 /------------\ - 필요한 컨테이너만
/              \
/   어댑터 단위  \ 어댑터 테스트
/________________\ - 단일 Config만 로드
```

**Import 패턴의 이점:**
- 테스트 범위에 맞는 Config만 Import
- 불필요한 빈 로드 시간 절약
- 테스트 격리 보장

---

## 정리

Import 패턴은 테스트를 쉽게 만든다.

**핵심 원칙:**
1. TestContainer로 실제 인프라 사용 (Mock DB 대신 Real DB)
2. Mock 어댑터로 외부 의존성 제거
3. `@Primary`로 프로덕션 빈 오버라이드
4. 어댑터 레벨 테스트로 빠른 피드백
5. 전체 통합 테스트로 E2E 검증

**테스트 구성 요소:**
- `TestContainerConfig`: 인프라 컨테이너
- `BaseTestContainerSpec`: 테스트 베이스 클래스
- `DatabaseCleanup`: 테스트 간 데이터 격리
- `TestConfig`: Mock 어댑터 스캔
- `Test*Adapter`: 외부 API Mock 구현

프로덕션과 테스트의 빈 구성이 일치하므로 테스트 결과를 신뢰할 수 있다.

---

## 시리즈 마무리

이 시리즈에서 다룬 내용:

1. **Part 1**: `@SpringBootApplication` 대신 `@EnableAutoConfiguration` + `@Import`로 명시적 의존성 관리
2. **Part 2**: `profiles.include`로 멀티앱 설정 합성
3. **Part 3**: Import 패턴이 테스트를 쉽게 만드는 방법

핵심은 **명시적 의존성**이다. 암묵적으로 동작하는 것보다 코드에서 바로 보이는 것이 낫다.
