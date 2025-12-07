# 테스트 전략/패턴

## TDD vs BDD

### TDD (Test-Driven Development)

개발자 관점의 테스트 주도 개발.

```
Red → Green → Refactor

1. Red: 실패하는 테스트 작성
2. Green: 테스트를 통과하는 최소한의 코드 작성
3. Refactor: 코드 개선 (테스트는 계속 통과)
```

**특징:**
- 구현 세부사항에 집중
- 단위 테스트 중심
- 개발자가 주도

### BDD (Behavior-Driven Development)

사용자/비즈니스 관점의 행동 주도 개발.

```gherkin
Feature: 주문 생성

Scenario: 재고가 있는 상품 주문
  Given 상품 A의 재고가 10개 있다
  When 사용자가 상품 A를 3개 주문한다
  Then 주문이 성공한다
  And 재고가 7개로 감소한다
```

**특징:**
- 시스템 행동에 집중
- 통합/인수 테스트 중심
- 비개발자와 협업 가능 (자연어)

### TDD vs BDD 비교

| 기준 | TDD | BDD |
|------|-----|-----|
| 관점 | 개발자 | 사용자/비즈니스 |
| 언어 | 코드 | 자연어 (Gherkin) |
| 테스트 수준 | 단위 | 통합/인수 |
| 도구 | JUnit, Kotest | Cucumber, SpecFlow |
| 협업 대상 | 개발자 | 개발자 + PO + QA |

### Three Amigos Meeting

BDD에서 기능 정의를 위한 협업 미팅.

| 역할 | 관점 |
|------|------|
| Product Owner | 비즈니스 가치, 요구사항 |
| Developer | 기술적 구현 가능성 |
| Tester | 엣지 케이스, 검증 방법 |

---

## Testing Pyramid vs Trophy

### Testing Pyramid (전통적)

```
        /\
       /  \     E2E (적게)
      /----\
     /      \   Integration (중간)
    /--------\
   /          \ Unit (많이)
  --------------
```

**철학**: 단위 테스트를 많이, E2E를 적게.

### Testing Trophy (현대적)

```
┌─────────────┐
│    E2E      │  (적게)
├─────────────┤
│             │
│ Integration │  (가장 많이)
│             │
├─────────────┤
│    Unit     │  (중간)
└─────────────┘
```

**철학**: 통합 테스트에 가장 투자.
> "Write tests. Not too many. Mostly integration." — Guillermo Rauch

### 비교

| 기준 | Pyramid | Trophy |
|------|---------|--------|
| 핵심 | 단위 테스트 | 통합 테스트 |
| 장점 | 빠른 피드백 | 실제 동작 검증 |
| 적합 | 복잡한 비즈니스 로직 | 인프라 연동 위주 |

### 실무 조합

| 대상 | 테스트 유형 |
|------|------------|
| 도메인 로직 | 단위 테스트 (빠른 피드백) |
| 어댑터/API | 통합 테스트 (실제 동작) |
| 외부 API | Mock 어댑터 |

### Ice Cream Cone (안티패턴)

Testing Pyramid를 뒤집은 형태. **피해야 할 구조**.

```
     ___________
    /           \     Manual Testing (가장 많음)
   /             \
  /_______________\
  |               |   UI/E2E Tests
  |_______________|
  |___|   Unit    |   (가장 적음)
```

**문제점:**
- 느린 피드백 루프
- 높은 유지보수 비용
- Flaky 테스트 증가
- 버그 발견이 늦음

---

## Test Double (테스트 대역)

테스트에서 실제 객체를 대체하는 객체들.

> Gerard Meszaros가 "Test Double"이라는 용어를 제안했다 (스턴트 더블에서 유래).

### 5가지 유형

| 유형 | 설명 | 예시 |
|------|------|------|
| **Dummy** | 전달만 되고 사용되지 않음 | 파라미터 채우기용 |
| **Stub** | 미리 정의된 값을 반환 | `given(...).willReturn(...)` |
| **Spy** | 호출 기록을 남기는 Stub | 이메일 발송 횟수 기록 |
| **Mock** | 기대 동작을 검증 | `verify(mock).method()` |
| **Fake** | 실제 동작하는 간단한 구현 | In-memory DB |

### State vs Behavior 검증

| 방식 | 설명 | 대상 |
|------|------|------|
| **State 검증** | 결과 상태 확인 | Stub, Fake |
| **Behavior 검증** | 메서드 호출 여부 확인 | Mock, Spy |

```kotlin
// State 검증 (Stub)
val result = service.calculate(input)
assertThat(result).isEqualTo(expected)

// Behavior 검증 (Mock)
service.process(order)
verify(eventPublisher).publish(any())
```

### 언제 무엇을 사용?

| 상황 | 추천 |
|------|------|
| 외부 API 호출 | Mock 또는 Fake |
| DB 조회 결과 | Stub |
| 이벤트 발행 여부 | Mock + verify |
| 복잡한 의존성 | Fake |

---

## Testcontainers

### 정의

Docker 컨테이너로 테스트 인프라를 구동하는 라이브러리.

### 기본 사용법

```kotlin
companion object {
    private val postgres = PostgreSQLContainer("postgres:15-alpine")
        .withDatabaseName("test")
        .apply { start() }
}
```

### 지원 컨테이너

| 컨테이너 | 용도 |
|----------|------|
| PostgreSQL | DB 테스트 |
| Redis | 캐시/락 테스트 |
| Kafka | 메시징 테스트 |
| LocalStack | AWS 서비스 Mock |
| Elasticsearch | 검색 테스트 |

### H2 vs Testcontainers

| 기준 | H2 | Testcontainers |
|------|-----|----------------|
| 속도 | 빠름 | 느림 |
| 프로덕션 일치 | 낮음 | 높음 |
| 설정 | 쉬움 | 중간 |
| 문법 호환 | PostgreSQL과 다름 | 동일 |

**Testcontainers 선택 이유:**
- PostgreSQL 전용 문법 (JSONB, ARRAY 등)
- "테스트 통과 → 프로덕션 실패" 방지

---

## Mock 패턴

### @MockBean

Spring Context 내 빈을 Mock으로 교체.

```kotlin
@SpringBootTest
class OrderServiceTest {
    @MockBean
    lateinit var paymentClient: PaymentClient

    @Test
    fun `주문 생성 시 결제 호출`() {
        given(paymentClient.charge(any())).willReturn(success)
        // ...
    }
}
```

**문제점:**
- @MockBean 조합이 다르면 Context 재생성
- 테스트 클래스마다 다른 조합 → 느림

### Mock 어댑터 패턴

Port 인터페이스를 구현한 테스트용 어댑터.

```kotlin
@Component("paymentAdapter")
@Primary  // 테스트에서 우선 선택
@Profile("test")
class TestPaymentAdapter : PaymentPort {
    private val responses = mutableMapOf<String, PaymentResult>()

    fun stubResponse(orderId: String, result: PaymentResult) {
        responses[orderId] = result
    }

    override fun charge(orderId: String): PaymentResult {
        return responses[orderId] ?: PaymentResult.success()
    }
}
```

### 비교

| 기준 | @MockBean | Mock 어댑터 |
|------|-----------|------------|
| Context 캐싱 | 조합마다 새로 | 재사용 가능 |
| 설정 위치 | 테스트마다 | Config 한 곳 |
| 유지보수 | 분산 | 집중 |
| Hexagonal 적합 | 낮음 | 높음 |

---

## Context Caching

### 동작 원리

Spring은 같은 설정의 ApplicationContext를 캐시한다.

```kotlin
// Test A - Context 1
@SpringBootTest
@MockBean UserRepository
class UserServiceTest

// Test B - Context 2 (새로 생성!)
@SpringBootTest
@MockBean OrderRepository
class OrderServiceTest

// Test C - Context 1 재사용
@SpringBootTest
@MockBean UserRepository
class UserControllerTest
```

### 캐시 유지 전략

**1. 공통 베이스 클래스**

```kotlin
@SpringBootTest
@ContextConfiguration(initializers = [TestContainerConfig::class])
abstract class BaseIntegrationTest {
    @MockBean lateinit var externalApiClient: ExternalApiClient
    // 모든 테스트가 같은 Mock 조합
}

class OrderServiceTest : BaseIntegrationTest()
class UserServiceTest : BaseIntegrationTest()
```

**2. Mock 어댑터로 @MockBean 제거**

@MockBean 대신 @Primary Mock 어댑터 → Context 하나로 통일.

---

## 테스트 격리

### 방식 비교

| 방식 | 속도 | 격리 | 구현 |
|------|------|------|------|
| @DirtiesContext | 느림 | 완벽 | 쉬움 |
| @Transactional 롤백 | 빠름 | 부분 | 쉬움 |
| TRUNCATE | 중간 | 완벽 | 중간 |

### TRUNCATE 방식

```kotlin
@Component
@Profile("test")
class DatabaseCleanup(private val entityManager: EntityManager) {

    @Transactional
    fun execute() {
        entityManager.createNativeQuery(
            "TRUNCATE TABLE orders, users RESTART IDENTITY CASCADE"
        ).executeUpdate()
    }
}

abstract class BaseIntegrationTest {
    @Autowired lateinit var databaseCleanup: DatabaseCleanup

    @BeforeEach
    fun setup() {
        databaseCleanup.execute()
    }
}
```

### @Transactional 주의점

```kotlin
@Transactional  // 테스트 후 롤백
@Test
fun `비동기 호출 테스트`() {
    service.createOrderAsync()  // 별도 트랜잭션!
    // 롤백되지 않음 → 테스트 오염
}
```

비동기/이벤트 테스트에서는 TRUNCATE 사용.

---

## Fixture 패턴

### 정의

테스트 데이터 생성을 위한 헬퍼.

### 구현

```kotlin
object UserFixture {
    fun aUser(
        id: UUID = UUID.randomUUID(),
        name: String = "Test User",
        email: String = "test@example.com",
        status: UserStatus = UserStatus.ACTIVE
    ) = User(id, name, email, status)
}

object OrderFixture {
    fun anOrder(
        id: UUID = UUID.randomUUID(),
        user: User = UserFixture.aUser(),
        items: List<OrderItem> = listOf(anOrderItem())
    ) = Order(id, user, items)

    fun anOrderItem(
        productId: UUID = UUID.randomUUID(),
        quantity: Int = 1,
        price: BigDecimal = BigDecimal("10000")
    ) = OrderItem(productId, quantity, price)
}

// 사용
val user = UserFixture.aUser(status = UserStatus.INACTIVE)
val order = OrderFixture.anOrder(user = user)
```

### 장점

- 기본값 제공 → 필요한 것만 오버라이드
- 일관된 테스트 데이터
- 변경 시 한 곳만 수정

---

## Flaky Test 방지

### 정의

간헐적으로 실패하는 테스트.

### 원인과 해결

| 원인 | 해결 |
|------|------|
| 시간 의존성 | Clock 주입, 고정 시간 |
| 비동기 처리 | Awaitility 사용 |
| 테스트 간 의존성 | 데이터 격리 |
| 랜덤 데이터 | Seed 고정 |

### 시간 고정

```kotlin
// 프로덕션 코드
class OrderService(private val clock: Clock) {
    fun create(): Order {
        return Order(createdAt = Instant.now(clock))
    }
}

// 테스트
val fixedClock = Clock.fixed(
    Instant.parse("2024-01-01T00:00:00Z"),
    ZoneOffset.UTC
)
val service = OrderService(fixedClock)
```

### Awaitility (비동기)

```kotlin
@Test
fun `비동기 저장 테스트`() {
    service.saveAsync(order)

    await()
        .atMost(5, SECONDS)
        .untilAsserted {
            assertThat(repository.findById(order.id)).isNotNull()
        }
}
```

---

## Source Set 분리

### 구조

```
src/
├── main/kotlin/...
├── test/kotlin/              ← 단위 테스트
│   └── domain/
│       └── OrderTest.kt
└── integrationTest/kotlin/   ← 통합 테스트
    └── api/
        └── OrderApiTest.kt
```

### Gradle 설정

```kotlin
sourceSets {
    val integrationTest by creating {
        kotlin.srcDir("src/integrationTest/kotlin")
        resources.srcDir("src/integrationTest/resources")
        compileClasspath += main.get().output + test.get().output
        runtimeClasspath += main.get().output + test.get().output
    }
}

tasks.register<Test>("integrationTest") {
    testClassesDirs = sourceSets["integrationTest"].output.classesDirs
    classpath = sourceSets["integrationTest"].runtimeClasspath
}
```

### 실행

```bash
./gradlew test            # 단위 테스트만 (빠름)
./gradlew integrationTest # 통합 테스트만
./gradlew check           # 전체
```

---

## FIRST 원칙

좋은 단위 테스트의 5가지 원칙.

| 원칙 | 설명 |
|------|------|
| **F**ast | 빠르게 실행되어야 함 (수 ms) |
| **I**solated | 다른 테스트와 독립적 |
| **R**epeatable | 언제 실행해도 같은 결과 |
| **S**elf-validating | 수동 확인 없이 Pass/Fail 판단 |
| **T**imely | 프로덕션 코드 직전에 작성 (TDD) |

### Fast

```kotlin
// 2000개 테스트 × 200ms = 6.5분
// 2000개 테스트 × 10ms = 20초

// 느림: 외부 호출
fun testWithRealApi() { ... }

// 빠름: Mock 사용
fun testWithMock() { ... }
```

### Isolated

```kotlin
// ❌ 테스트 간 의존성
companion object {
    var sharedCounter = 0  // 다른 테스트에 영향
}

// ✅ 격리된 테스트
@BeforeEach
fun setup() {
    counter = 0  // 매 테스트마다 초기화
}
```

### Repeatable

```kotlin
// ❌ 환경에 따라 결과가 다름
assertThat(LocalDate.now()).isEqualTo(expected)

// ✅ 고정된 시간
val fixedClock = Clock.fixed(...)
assertThat(LocalDate.now(fixedClock)).isEqualTo(expected)
```

---

## 테스트 구조 패턴

### AAA (Arrange-Act-Assert)

```kotlin
@Test
fun `주문 생성 시 재고 감소`() {
    // Arrange (준비)
    val product = Product(stock = 10)
    val service = OrderService(productRepository)

    // Act (실행)
    service.createOrder(product.id, quantity = 3)

    // Assert (검증)
    assertThat(product.stock).isEqualTo(7)
}
```

### GWT (Given-When-Then)

BDD 스타일. AAA와 본질적으로 동일.

```kotlin
@Test
fun `주문 생성 시 재고 감소`() {
    // Given
    val product = Product(stock = 10)

    // When
    service.createOrder(product.id, quantity = 3)

    // Then
    assertThat(product.stock).isEqualTo(7)
}
```

### AAA vs GWT

| 기준 | AAA | GWT |
|------|-----|-----|
| 관점 | 기술적 | 비즈니스 |
| 가독성 | 개발자 | 비개발자도 이해 |
| 주 사용처 | 단위 테스트 | BDD/인수 테스트 |

---

## Code Coverage

### 커버리지 유형

| 유형 | 설명 | 측정 |
|------|------|------|
| **Line** | 실행된 라인 수 | 기본 |
| **Branch** | 조건문의 true/false 분기 | 더 엄격 |
| **Function** | 호출된 함수 수 | 간단 |
| **Condition** | 각 Boolean 조건 | 가장 엄격 |

### Line vs Branch Coverage

```kotlin
fun process(x: Int): Int {
    if (x < 0) return -x
    return x
}

// 테스트: process(5) → 결과: 5
// Line Coverage: 100% (모든 라인 실행)
// Branch Coverage: 50% (x >= 0만 테스트)
```

**중요**: 100% Line Coverage ≠ 버그 없음

### 커버리지의 한계

```kotlin
fun add(a: Int, b: Int) = a + b

@Test
fun test() {
    add(1, 2)  // 호출만 하고 검증 안 함
}
// Line Coverage: 100%
// 하지만 실제로 검증하지 않음!
```

---

## Mutation Testing

커버리지의 한계를 극복하는 테스트 품질 측정 방법.

### 동작 원리

```
1. 코드에 "돌연변이" 주입
   - a + b → a - b
   - x > 0 → x >= 0
   - return true → return false

2. 테스트 실행

3. 결과 분석
   - 테스트 실패 → Mutant Killed (좋음)
   - 테스트 통과 → Mutant Survived (나쁨)
```

### PITest (Java/Kotlin)

```kotlin
// build.gradle.kts
plugins {
    id("info.solidsoft.pitest") version "1.15.0"
}

pitest {
    targetClasses.set(listOf("com.example.*"))
    mutators.set(listOf("DEFAULTS"))
    outputFormats.set(listOf("HTML"))
}
```

### Coverage vs Mutation Score

| 지표 | 의미 | 한계 |
|------|------|------|
| Code Coverage | 코드 실행 여부 | 검증 품질 모름 |
| Mutation Score | 테스트 검증 품질 | 실행 시간 오래 걸림 |

```
100% Code Coverage + 0% Mutation Score 가능
→ 실행만 하고 assert가 없는 테스트
```

---

## Contract Testing

마이크로서비스 간 API 계약을 검증하는 테스트.

### Consumer-Driven Contract

```
Consumer가 기대하는 계약 정의 → Provider가 계약 준수 검증
```

### Pact

```kotlin
// Consumer 측
@Pact(consumer = "OrderService", provider = "PaymentService")
fun paymentPact(builder: PactDslWithProvider): RequestResponsePact {
    return builder
        .given("사용자가 존재함")
        .uponReceiving("결제 요청")
            .path("/payments")
            .method("POST")
        .willRespondWith()
            .status(200)
            .body("""{"status": "success"}""")
        .toPact()
}

// Provider 측에서 이 계약을 검증
```

### 장점

| 기존 방식 | Contract Testing |
|----------|------------------|
| E2E 테스트 필요 | 각 서비스 독립 테스트 |
| 느리고 불안정 | 빠르고 안정적 |
| 통합 환경 필요 | 로컬에서 실행 가능 |

---

## 관련 Interview 문서

- [05-testcontainers.md](../interview/05-testcontainers.md)
- [06-testing-strategy.md](../interview/06-testing-strategy.md)

---

## 참고 자료

- [Martin Fowler - Mocks Aren't Stubs](https://martinfowler.com/articles/mocksArentStubs.html)
- [Martin Fowler - The Practical Test Pyramid](https://martinfowler.com/articles/practical-test-pyramid.html)
- [PITest - Mutation Testing](https://pitest.org/)
- [Pact - Contract Testing](https://docs.pact.io/)

---

*다음: [04-database.md](./04-database.md)*
