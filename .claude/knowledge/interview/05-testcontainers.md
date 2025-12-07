# Testcontainers 기반 통합 테스트 전략

## 이력서 연결

> "Testcontainers 기반 테스트 환경 구축으로 커버리지 90% 달성"
> "프로덕션과 동일한 테스트 환경으로 배포 자신감 향상"

---

## 핵심 답변 (STAR)

### Situation (상황)
- 42dot Vehicle Platform, 마이크로서비스 아키텍처
- 기존: H2 인메모리 DB로 테스트 → 프로덕션(PostgreSQL)과 SQL 문법 차이
- @MockBean 남용 → 테스트는 통과하지만 프로덕션에서 실패

### Task (과제)
- 프로덕션과 동일한 테스트 환경 구축
- 테스트 속도와 신뢰성 모두 확보
- 외부 API 의존성 제거

### Action (행동)
1. **Source Set 분리**
   - `src/test`: 단위 테스트 (Spring 없이)
   - `src/integrationTest`: 통합 테스트 (Testcontainers)

2. **Testcontainers 도입**
   - PostgreSQL, Redis, Kafka를 Docker 컨테이너로 구동
   - `ApplicationContextInitializer`로 동적 프로퍼티 주입

3. **Mock 어댑터 패턴**
   - 내부 인프라: 실제 Testcontainers 사용
   - 외부 API: `@Primary` Mock 어댑터로 교체

4. **테스트 격리**
   - `DatabaseCleanup`: 테스트 전 `TRUNCATE CASCADE`
   - Context 재사용: `@MockBean` 조합 통일

### Result (결과)
- 테스트 커버리지 90% 달성
- "테스트 통과 → 프로덕션 실패" 사례 제거
- 배포 자신감 향상

---

## 예상 질문

### Q1: 왜 H2 대신 Testcontainers를 사용했나요?

**답변:**
H2의 문제:
- PostgreSQL과 SQL 문법 차이 (JSONB, ARRAY 타입 등)
- 트랜잭션 동작 차이
- 테스트 통과 → 프로덕션 실패

Testcontainers의 장점:
- 프로덕션과 **동일한 PostgreSQL** 사용
- Docker 컨테이너로 격리된 환경
- PostgreSQL, Redis, Kafka, LocalStack 등 다양한 지원

```kotlin
private val postgres = PostgreSQLContainer("postgres:15-alpine")
    .withDatabaseName("app_test")
    .apply { start() }
```

### Q2: @MockBean의 문제점이 뭔가요?

**답변:**
`@MockBean`은 편리하지만 숨겨진 비용이 있다.

```kotlin
// 각 테스트마다 다른 @MockBean 조합 → Context 새로 생성
@SpringBootTest
class UserServiceTest {
    @MockBean lateinit var userRepository: UserRepository  // Context 1
}

@SpringBootTest
class OrderServiceTest {
    @MockBean lateinit var orderRepository: OrderRepository  // Context 2 (새로 생성!)
}
```

문제:
- `@MockBean` 조합이 다르면 Context 캐시 불가
- 테스트 클래스마다 Context 재로드 → 수십 초 지연
- Mock이 늘어날수록 테스트와 프로덕션 괴리

해결:
- 공통 베이스 클래스로 `@MockBean` 통일
- 또는 **Mock 대신 실제 구현 테스트** (Testcontainers)

### Q3: Mock 어댑터 패턴이 뭔가요?

**답변:**
핵심 원칙: **내부 인프라는 실제로 테스트, 외부 API만 Mock**

| 대상 | Mock 여부 | 이유 |
|-----|----------|------|
| PostgreSQL | ❌ 실제 | SQL 문법, 트랜잭션 검증 |
| Redis | ❌ 실제 | 캐시 만료, 분산 락 검증 |
| Kafka | ❌ 실제 | 직렬화, 컨슈머 동작 검증 |
| **외부 API** | ✅ Mock | 네트워크 의존성 제거 |

```kotlin
@Component("vdpServiceAdapter")
@Primary  // 테스트에서 이 빈이 우선 선택
class TestVdpServiceAdapter : VdpOut {
    private val store = mutableMapOf<String, VdpDeviceInfo>()

    override fun registerDevice(deviceSourceId: String): VdpDeviceInfo {
        // 인메모리 저장소로 실제 API 호출 없이 동작
        return VdpDeviceInfo(deviceId = UUID.randomUUID())
    }
}
```

Hexagonal Architecture의 Port 인터페이스를 활용하여 Adapter를 교체한다.

### Q4: Source Set 분리는 왜 했나요?

**답변:**
`src/test`에 모든 테스트를 넣으면:
- 단위/통합 테스트가 섞여 실행 시간 예측 어려움
- CI에서 선택적 실행 어려움

분리 후:
- `src/test`: 단위 테스트 (Spring 없이, 빠름)
- `src/integrationTest`: 통합 테스트 (Testcontainers)

```kotlin
// build.gradle.kts
sourceSets {
    val integrationTest by creating {
        kotlin.srcDir("src/integrationTest/kotlin")
        // ...
    }
}

tasks.register<Test>("integrationTest") {
    testClassesDirs = sourceSets["integrationTest"].output.classesDirs
    // ...
}
```

- `./gradlew test`: 단위 테스트만 (빠름)
- `./gradlew integrationTest`: 통합 테스트만

### Q5: 테스트 격리는 어떻게 했나요?

**답변:**
각 테스트는 독립적이어야 한다. 이전 테스트 데이터가 영향을 주면 안 된다.

```kotlin
@Component
@Profile("integration")
class DatabaseCleanup(private val entityManager: EntityManager) {

    @Transactional
    fun execute() {
        entityManager.createNativeQuery(
            "TRUNCATE TABLE $tableNames RESTART IDENTITY CASCADE"
        ).executeUpdate()
    }
}
```

- `RESTART IDENTITY`: Auto Increment ID 초기화
- `CASCADE`: FK 제약 조건 함께 처리
- `@DirtiesContext` 대신 → Context 재사용 + 데이터만 정리

---

## 꼬리 질문 대비

### Q: Context 재사용은 어떻게 했나요?

**답변:**
Spring은 같은 설정의 Context를 캐시한다. `@MockBean` 조합이 다르면 캐시가 깨진다.

공통 베이스 클래스:

```kotlin
@SpringBootTest(
    webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
    classes = [Application::class, TestConfig::class]
)
@ContextConfiguration(initializers = [TestContainerConfig::class])
@ActiveProfiles("integration")
abstract class BaseTestContainerSpec(
    protected val mockMvc: MockMvc,
    private val databaseCleanup: DatabaseCleanup
) : BehaviorSpec() {

    init {
        beforeSpec { databaseCleanup.execute() }
    }
}
```

모든 통합 테스트가 이 클래스를 상속 → 같은 Context 재사용

### Q: CI 전략은 어떻게 설정했나요?

**답변:**

| 테스트 유형 | 실행 시점 | 이유 |
|------------|----------|------|
| 단위 테스트 | 모든 커밋 | 빠른 피드백 |
| 통합 테스트 | MR 검토, 수동 | Testcontainers 시간 소요 |

```yaml
# GitHub Actions
unit-test:
  runs-on: ubuntu-latest
  steps:
    - run: ./gradlew test

integration-test:
  runs-on: ubuntu-latest
  if: github.event_name == 'workflow_dispatch'  # 수동 실행
  steps:
    - run: ./gradlew integrationTest
```

### Q: Testing Pyramid vs Testing Trophy 차이는?

**답변:**

**Testing Pyramid** (전통적):
- 단위 테스트를 가장 많이, E2E를 적게
- 빠른 피드백, 세밀한 검증

**Testing Trophy** (현대적):
- 통합 테스트에 가장 투자
- "Write tests. Not too many. Mostly integration." — Guillermo Rauch

저희는 두 접근의 장점을 조합:
1. **도메인 로직** → 단위 테스트 (빠른 피드백)
2. **어댑터/API** → 통합 테스트 (실제 동작 검증)
3. **외부 API** → Mock 어댑터 (의존성 제거)

### Q: 테스트 속도는 어떻게 개선했나요?

**답변:**
1. **Context 재사용**: 베이스 클래스 통일
2. **컨테이너 공유**: `companion object`로 여러 테스트가 같은 컨테이너 사용
3. **Source Set 분리**: 단위/통합 테스트 선택 실행
4. **필요한 Config만 Import**: 범위에 맞는 빈만 로드

```kotlin
// 컨테이너 공유
companion object {
    private val postgres = PostgreSQLContainer("postgres:15-alpine")
        .apply { start() }  // 한 번만 시작
}
```

빌드 시간: 10분 → 4분으로 단축 (사례 기준)

---

## 관련 개념 정리

| 개념 | 설명 |
|------|------|
| Testcontainers | Docker 컨테이너로 테스트 인프라 구동 |
| Source Set | Gradle의 소스 코드 분리 단위 |
| @MockBean | Spring Context 내 빈을 Mock으로 교체 |
| @Primary | 같은 타입의 빈 중 우선 선택 |
| Context Caching | 같은 설정의 ApplicationContext 재사용 |
| DatabaseCleanup | 테스트 간 데이터 격리 |
| Testing Pyramid | 단위 > 통합 > E2E 비율 |
| Testing Trophy | 통합 테스트 중심 전략 |

---

## 디렉토리 구조

```
src/
├── main/kotlin/...
├── test/                      ← 단위 테스트
│   └── kotlin/
│       └── domain/
│           └── VehicleTest.kt
└── integrationTest/           ← 통합 테스트
    ├── kotlin/
    │   ├── TestContainerConfig.kt
    │   ├── support/
    │   │   └── BaseTestContainerSpec.kt
    │   └── test/
    │       ├── config/
    │       │   ├── TestConfig.kt
    │       │   └── DatabaseCleanup.kt
    │       └── mock/
    │           └── TestVdpServiceAdapter.kt
    └── resources/
        └── application.yml
```

---

## 테스트 레벨별 구성

```
┌─────────────────────────────────────────────────────────────┐
│                        E2E 테스트                           │
│                 전체 앱, 모든 컨테이너                       │
│                     상대 시간: ~5x                          │
├─────────────────────────────────────────────────────────────┤
│                     통합 테스트                              │
│              필요한 컨테이너만, API 검증                     │
│                     상대 시간: ~3x                          │
├─────────────────────────────────────────────────────────────┤
│                     단위 테스트                              │
│           도메인 로직, Spring 없이, 빠른 피드백              │
│                     상대 시간: 1x                           │
└─────────────────────────────────────────────────────────────┘
```

| 레벨 | Import 범위 | 사용 컨테이너 | 상대 시간 |
|-----|------------|-------------|----------|
| 단위 | 없음 | 없음 | 1x |
| 어댑터 | PersistenceConfig | PostgreSQL만 | ~2x |
| 서비스 통합 | 어댑터 + UseCase | PostgreSQL + Redis | ~3x |
| E2E | 전체 앱 | 전체 | ~5x |

---

## 기술 선택과 Trade-off

### 왜 Testcontainers를 선택했는가?

**대안 비교:**

| 방식 | 프로덕션 일치 | 속도 | 설정 복잡도 | CI 호환성 |
|------|--------------|------|-------------|-----------|
| **H2 인메모리** | 낮음 | 매우 빠름 | 쉬움 | 좋음 |
| **Embedded (Flapdoodle 등)** | 중간 | 빠름 | 중간 | 좋음 |
| **Testcontainers** | 높음 | 느림 | 중간 | Docker 필요 |
| **실제 인프라** | 완벽 | 느림 | 어려움 | 나쁨 |

**Testcontainers 선택 이유:**
- H2: PostgreSQL 문법 차이로 테스트 통과 → 프로덕션 실패 경험
- Embedded: PostgreSQL은 공식 Embedded 버전 없음
- **Testcontainers가 "프로덕션과 동일한 환경"의 현실적 선택**

### @MockBean vs Mock 어댑터

| 기준 | @MockBean | Mock 어댑터 |
|------|-----------|------------|
| Context 캐싱 | 조합마다 새 Context | 재사용 가능 |
| 설정 위치 | 테스트 클래스마다 | 테스트 Config 한 곳 |
| 프로덕션 빈 교체 | 런타임 | 빌드 타임 |
| 실수 가능성 | 높음 | 낮음 |

**Mock 어댑터 선택 이유:**
- @MockBean 조합이 다르면 Context 재생성 → 테스트 속도 저하
- Mock 어댑터는 @Primary로 한 번 설정 → 모든 테스트 공유
- Hexagonal Architecture의 Port 교체 패턴과 일치

### Source Set 분리 Trade-off

| 기준 | 단일 src/test | 분리 (test + integrationTest) |
|------|--------------|------------------------------|
| 설정 복잡도 | 단순 | Gradle 설정 필요 |
| 선택 실행 | 어려움 | 쉬움 |
| 빌드 시간 제어 | 불가 | 가능 |
| CI 파이프라인 | 단순 | 유연 |

**분리 선택 이유:**
- 단위 테스트만 빠르게 돌리고 싶을 때가 많음
- CI에서 단계별 실행 (PR: 단위만, Merge: 통합 포함)
- 설정 복잡도는 한 번만 투자하면 됨

### 테스트 격리 전략

**대안:**

| 방식 | 속도 | 격리 수준 | 구현 복잡도 |
|------|------|----------|-------------|
| **@DirtiesContext** | 매우 느림 | 완벽 | 쉬움 |
| **@Transactional 롤백** | 빠름 | 부분적 | 쉬움 |
| **TRUNCATE** | 중간 | 완벽 | 중간 |
| **테이블 Drop/Create** | 느림 | 완벽 | 중간 |

**TRUNCATE 선택 이유:**
- @DirtiesContext: Context 재생성 비용 큼
- @Transactional: 트랜잭션 경계 문제 (실제와 다름)
- **TRUNCATE가 속도와 격리의 균형점**

### Testing Pyramid vs Trophy

| 접근 | 핵심 | 적합한 상황 |
|------|------|-------------|
| **Pyramid** | 단위 테스트 많이 | 복잡한 비즈니스 로직 |
| **Trophy** | 통합 테스트 중심 | 인프라 연동 위주 |

**하이브리드 선택 이유:**
- 도메인 로직: 단위 테스트 (빠른 피드백)
- 어댑터/API: 통합 테스트 (실제 동작 검증)
- 둘 다 중요하지만, 우리 서비스는 인프라 연동이 많아 통합 테스트 비중 높임

---

## 블로그 링크

- [Testcontainers 기반 통합 테스트 전략](https://gyeom.github.io/dev-notes/posts/2024-08-10-testcontainers-integration-test-strategy/)

---

*다음: [06-testing-strategy.md](./06-testing-strategy.md)*
