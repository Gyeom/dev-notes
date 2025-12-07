# 테스트 전략

## 이력서 연결

> "테스트 커버리지 90% 달성"
> "프로덕션과 동일한 테스트 환경 구축"
> "Mock은 외부 API 연동에만 제한적 사용"

---

## 핵심 내용

이 문서는 [05-testcontainers.md](./05-testcontainers.md)의 보충 자료다.
테스트 피라미드, Mock 전략, Context 관리에 대한 추가 질문을 다룬다.

---

## 예상 질문

### Q1: Testing Pyramid vs Testing Trophy 차이는?

**답변:**

```
Testing Pyramid (전통적)       Testing Trophy (현대적)

      /\                           ┌───────────┐
     /  \  E2E                     │   E2E     │
    /────\                         └───────────┘
   /      \                        ┌───────────┐
  / Integr \                       │           │
 /──────────\                      │Integration│ ← 가장 두꺼움
/            \                     │           │
──────────────                     └───────────┘
   Unit (가장 넓음)                ┌───────────┐
                                   │   Unit    │
                                   └───────────┘
```

| 접근법 | 핵심 철학 | 적합한 상황 |
|--------|----------|-------------|
| **Pyramid** | 단위 테스트 많이, E2E 적게 | 복잡한 비즈니스 로직 |
| **Trophy** | 통합 테스트에 집중 | 인프라 연동이 많은 서비스 |

**우리 프로젝트:**
- 도메인 로직 → 단위 테스트 (빠른 피드백)
- 어댑터/API → 통합 테스트 (실제 동작 검증)
- 외부 API → Mock 어댑터

### Q2: 단위 테스트와 통합 테스트의 경계는?

**답변:**

| 기준 | 단위 테스트 | 통합 테스트 |
|------|-----------|------------|
| Spring Context | ❌ 없음 | ✅ 있음 |
| 외부 의존성 | Mock/Stub | 실제 (Testcontainers) |
| 실행 속도 | 매우 빠름 | 느림 |
| 검증 대상 | 비즈니스 로직 | 컴포넌트 통합 |

```kotlin
// 단위 테스트 (Spring 없이)
class VehicleTest : StringSpec({
    "차량 상태가 INACTIVE이면 활성화할 수 있다" {
        val vehicle = Vehicle(status = VehicleStatus.INACTIVE)
        vehicle.activate()
        vehicle.status shouldBe VehicleStatus.ACTIVE
    }
})

// 통합 테스트 (Spring Context)
@SpringBootTest
class VehicleApiTest : BaseTestContainerSpec() {
    @Test
    fun `차량 생성 API 호출 시 DB에 저장된다`() {
        // Testcontainers PostgreSQL 사용
        mockMvc.post("/vehicles") { ... }
        vehicleRepository.findAll() shouldHaveSize 1
    }
}
```

### Q3: @MockBean 사용 시 Context 재사용 문제는?

**답변:**
`@MockBean` 조합이 다르면 Context 캐시가 깨진다.

```kotlin
// Test A: UserRepository 모킹
@SpringBootTest
class UserServiceTest {
    @MockBean lateinit var userRepository: UserRepository  // Context 1
}

// Test B: OrderRepository 모킹
@SpringBootTest
class OrderServiceTest {
    @MockBean lateinit var orderRepository: OrderRepository  // Context 2 (새로 생성!)
}
```

**해결책:**

1. **공통 베이스 클래스**
```kotlin
@SpringBootTest
abstract class BaseIntegrationTest {
    @MockBean lateinit var externalApiClient: ExternalApiClient
    // 모든 테스트가 같은 Mock 조합 사용
}
```

2. **Mock 어댑터 패턴**
```kotlin
// @MockBean 대신 @Primary Mock 빈
@Component
@Primary
class TestExternalApiAdapter : ExternalApiPort {
    override fun call() = TestData.response()
}
```

### Q4: 테스트 데이터 관리는 어떻게?

**답변:**

**1. Builder/Factory 패턴**
```kotlin
object VehicleFixture {
    fun aVehicle(
        id: UUID = UUID.randomUUID(),
        name: String = "Test Vehicle",
        status: VehicleStatus = VehicleStatus.ACTIVE
    ) = Vehicle(id, name, status)
}

// 사용
val vehicle = VehicleFixture.aVehicle(status = VehicleStatus.INACTIVE)
```

**2. 테스트 간 격리**
```kotlin
@Component
class DatabaseCleanup(
    private val entityManager: EntityManager
) {
    @Transactional
    fun execute() {
        entityManager.createNativeQuery(
            "TRUNCATE TABLE $tables RESTART IDENTITY CASCADE"
        ).executeUpdate()
    }
}
```

**3. 테스트 실행 순서 무관하게**
- 각 테스트 전 데이터 초기화
- 테스트 간 의존성 없음

### Q5: Flaky Test는 어떻게 해결하나요?

**답변:**
Flaky Test는 간헐적으로 실패하는 테스트다.

**흔한 원인과 해결:**

| 원인 | 해결 |
|------|------|
| 시간 의존성 | `Clock` 주입, 고정된 시간 |
| 비동기 처리 | Awaitility 사용 |
| 테스트 간 의존성 | 데이터 격리 |
| 랜덤 데이터 | Seed 고정 |

```kotlin
// ❌ Flaky
assertThat(result.createdAt).isEqualTo(Instant.now())

// ✅ 안정적
val fixedClock = Clock.fixed(Instant.parse("2024-01-01T00:00:00Z"), ZoneOffset.UTC)
assertThat(result.createdAt).isEqualTo(fixedClock.instant())

// 비동기 대기
await().atMost(5, SECONDS).untilAsserted {
    assertThat(repository.findById(id)).isNotNull()
}
```

---

## 관련 개념 정리

| 개념 | 설명 |
|------|------|
| Testing Pyramid | 단위 테스트 많이, E2E 적게 |
| Testing Trophy | 통합 테스트 중심 |
| Context Caching | 같은 설정의 Context 재사용 |
| Fixture | 테스트 데이터 생성 헬퍼 |
| Flaky Test | 간헐적으로 실패하는 테스트 |
| Awaitility | 비동기 테스트 유틸리티 |

---

## 테스트 레벨별 책임

```
┌─────────────────────────────────────────────┐
│           E2E Test                          │
│   전체 시스템, 사용자 시나리오              │
│   Selenium, Cypress                         │
├─────────────────────────────────────────────┤
│         Integration Test                    │
│   API 통합, DB 연동, 메시징                 │
│   Testcontainers, MockMvc                   │
├─────────────────────────────────────────────┤
│            Unit Test                        │
│   도메인 로직, 순수 함수                    │
│   Kotest, JUnit                             │
└─────────────────────────────────────────────┘
```

---

*다음: [07-openfga-rebac.md](./07-openfga-rebac.md)*
