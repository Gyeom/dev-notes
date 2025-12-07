# Spring / Kotlin 핵심 개념

## Spring Boot Auto-Configuration

### 동작 원리

```
1. @SpringBootApplication
   └── @EnableAutoConfiguration
       └── AutoConfigurationImportSelector

2. META-INF/spring/org.springframework.boot.autoconfigure.AutoConfiguration.imports 읽기

3. @Conditional 조건 평가
   └── 조건 충족 시 Bean 등록
```

### @Conditional 종류

| 어노테이션 | 조건 |
|-----------|------|
| `@ConditionalOnClass` | 클래스패스에 클래스 존재 |
| `@ConditionalOnMissingBean` | Bean이 없을 때 |
| `@ConditionalOnProperty` | 프로퍼티 값 일치 |
| `@ConditionalOnWebApplication` | 웹 애플리케이션일 때 |

### 커스텀 Auto-Configuration

```kotlin
@AutoConfiguration
@ConditionalOnClass(MyService::class)
@ConditionalOnProperty(prefix = "my", name = ["enabled"], havingValue = "true")
class MyAutoConfiguration {
    @Bean
    @ConditionalOnMissingBean
    fun myService(): MyService = DefaultMyService()
}
```

### 디버깅

```properties
# 어떤 Auto-Configuration이 적용되었는지 확인
debug=true
```

---

## Spring Core

### IoC (Inversion of Control)

객체의 생성과 생명주기 관리를 프레임워크에 위임한다.

```kotlin
// ❌ 직접 생성 (제어권이 개발자에게)
class OrderService {
    private val repository = OrderRepository()  // 직접 생성
}

// ✅ IoC (제어권이 Spring에게)
@Service
class OrderService(
    private val repository: OrderRepository  // Spring이 주입
)
```

### DI (Dependency Injection)

의존성을 외부에서 주입받는 패턴.

| 방식 | 권장 | 이유 |
|------|------|------|
| **생성자 주입** | ✅ | 불변성, 필수 의존성 명확, 테스트 용이 |
| 필드 주입 | ❌ | 테스트 어려움, 불변성 보장 불가 |
| Setter 주입 | △ | 선택적 의존성에만 |

```kotlin
// 생성자 주입 (권장)
@Service
class OrderService(
    private val orderRepository: OrderRepository,
    private val eventPublisher: EventPublisher
)

// 필드 주입 (비권장)
@Service
class OrderService {
    @Autowired
    private lateinit var orderRepository: OrderRepository
}
```

### 순환 의존성 (Circular Dependency)

```kotlin
// ❌ 순환 참조
@Service
class ServiceA(private val serviceB: ServiceB)

@Service
class ServiceB(private val serviceA: ServiceA)
```

**해결 방법:**

```kotlin
// 1. @Lazy
@Service
class ServiceA(@Lazy private val serviceB: ServiceB)

// 2. Setter 주입 (비권장)
@Service
class ServiceA {
    @Autowired
    lateinit var serviceB: ServiceB
}

// 3. 설계 개선 (권장)
// ServiceA와 ServiceB가 공통으로 의존하는 ServiceC 추출
```

---

## Bean 생명주기

```
1. 인스턴스화 (Instantiation)
        ↓
2. 의존성 주입 (Dependency Injection)
        ↓
3. 초기화 콜백 (Initialization)
   - @PostConstruct
   - InitializingBean.afterPropertiesSet()
   - @Bean(initMethod = "...")
        ↓
4. 사용 (Ready to Use)
        ↓
5. 소멸 콜백 (Destruction)
   - @PreDestroy
   - DisposableBean.destroy()
   - @Bean(destroyMethod = "...")
```

```kotlin
@Component
class CacheWarmer(private val cache: CacheManager) {
    @PostConstruct
    fun warmUp() {
        cache.loadHotData()
    }

    @PreDestroy
    fun cleanup() {
        cache.flush()
    }
}
```

### Bean Scope

| Scope | 설명 | 사용 |
|-------|------|------|
| **singleton** | 기본값, 앱에 하나 | 대부분 |
| prototype | 요청마다 새로 생성 | 상태 있는 빈 |
| request | HTTP 요청마다 | 웹 |
| session | HTTP 세션마다 | 웹 |

---

## @Transactional

Spring AOP 기반 **프록시 패턴** 사용.

```
Client → Proxy → Target (Service)
           │
           ├─ 트랜잭션 시작 (BEGIN)
           │
           ├─ 실제 메서드 실행
           │
           └─ 트랜잭션 종료 (COMMIT/ROLLBACK)
```

### 주의점

| 상황 | 동작 |
|------|------|
| 같은 클래스 내부 호출 | 프록시 우회, 트랜잭션 미적용 |
| private 메서드 | 프록시 미적용 |
| 체크 예외 | 기본적으로 롤백 안 함 |

```kotlin
@Service
class OrderService {
    @Transactional
    fun createOrder() {
        internalMethod()  // ❌ 트랜잭션 미적용 (내부 호출)
    }

    @Transactional
    fun internalMethod() { }
}
```

**해결책**: 별도 클래스로 분리, `self.method()` 패턴, AspectJ 모드.

### 트랜잭션 전파 (Propagation)

| 옵션 | 동작 |
|------|------|
| **REQUIRED** | 기존 트랜잭션 사용, 없으면 새로 생성 (기본) |
| **REQUIRES_NEW** | 항상 새 트랜잭션 생성 (기존 일시 중단) |
| **NESTED** | 중첩 트랜잭션 (Savepoint) |
| **SUPPORTS** | 있으면 사용, 없으면 없이 실행 |
| **NOT_SUPPORTED** | 트랜잭션 없이 실행 (기존 일시 중단) |
| **MANDATORY** | 기존 트랜잭션 필수, 없으면 예외 |
| **NEVER** | 트랜잭션 있으면 예외 |

```kotlin
@Service
class OrderService(private val notificationService: NotificationService) {

    @Transactional
    fun createOrder(order: Order) {
        orderRepository.save(order)

        // 알림 실패해도 주문은 유지
        notificationService.sendNotification(order)
    }
}

@Service
class NotificationService {
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    fun sendNotification(order: Order) {
        // 별도 트랜잭션에서 실행
        // 실패해도 상위 트랜잭션에 영향 없음
    }
}
```

### 읽기 전용 트랜잭션

```kotlin
@Transactional(readOnly = true)
fun findAll(): List<Order> {
    return orderRepository.findAll()
}
```

**효과:**
- Hibernate: FlushMode.NEVER (Dirty Checking 안 함)
- 일부 DB: 읽기 전용 힌트로 최적화
- JPA: 스냅샷 저장 안 함 (메모리 절약)

---

## @ComponentScan vs @Import

### @ComponentScan

```kotlin
@SpringBootApplication  // 내부에 @ComponentScan 포함
class Application
```

**문제점:**
- 어떤 빈이 등록되는지 코드에서 보이지 않음
- 원치 않는 빈이 등록될 수 있음
- 멀티 모듈에서 혼란

### @Import

```kotlin
@EnableAutoConfiguration
@Import(
    WebAdapterConfig::class,
    PersistenceAdapterConfig::class,
    UseCaseConfig::class
)
class Application
```

**장점:**
- 명시적 빈 구성
- 어떤 어댑터가 활성화되는지 한눈에 파악
- 테스트에서 필요한 Config만 Import

### 경계 설정

| 구분 | 설정 방식 | 예시 |
|------|----------|------|
| 인프라 | AutoConfiguration (암묵적) | DataSource, JPA, Kafka |
| 비즈니스 | @Import (명시적) | Controller, Adapter, UseCase |

---

## Spring AOP

**관점 지향 프로그래밍**으로 횡단 관심사를 분리.

```kotlin
@Aspect
@Component
class LoggingAspect {
    @Around("@annotation(Loggable)")
    fun logExecution(joinPoint: ProceedingJoinPoint): Any? {
        val start = System.currentTimeMillis()
        return try {
            joinPoint.proceed()
        } finally {
            val elapsed = System.currentTimeMillis() - start
            log.info("${joinPoint.signature.name} executed in ${elapsed}ms")
        }
    }
}
```

### 주요 개념

| 용어 | 설명 |
|------|------|
| Aspect | 횡단 관심사 모듈 |
| Advice | 실제 수행될 로직 (Before, After, Around) |
| Pointcut | 어디에 적용할지 정의 |
| JoinPoint | 메서드 실행 시점 |

### Spring AOP vs AspectJ

| 기준 | Spring AOP | AspectJ |
|------|-----------|---------|
| 방식 | 프록시 기반 | 바이트코드 조작 |
| 성능 | 약간 느림 | 빠름 |
| 적용 범위 | public 메서드만 | 모든 곳 |
| 설정 | 간단 | 복잡 |

---

## Kotlin JPA

### 필수 플러그인

```kotlin
// build.gradle.kts
plugins {
    kotlin("plugin.jpa")  // all-open + no-arg 자동 적용
}
```

- **all-open**: JPA 프록시를 위해 클래스를 open으로
- **no-arg**: Hibernate 리플렉션용 기본 생성자

### data class 사용 금지

```kotlin
// ❌ 문제: equals/hashCode가 모든 필드 포함
data class Vehicle(val id: UUID, var name: String)

// ✅ 권장: 일반 class + 직접 구현
class Vehicle(
    @Id val id: UUID
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is Vehicle) return false
        return id == other.id  // ID만 비교
    }
    override fun hashCode() = id.hashCode()
}
```

### Persistable 인터페이스

UUID PK 사용 시 불필요한 SELECT 방지.

```kotlin
@Entity
class Vehicle(
    @Id
    val id: UUID = UUID.randomUUID()
) : Persistable<UUID> {

    @CreatedDate
    @Column(updatable = false)
    var createdAt: Instant? = null

    override fun getId(): UUID = id

    override fun isNew(): Boolean = createdAt == null
}
```

`isNew()`가 `true`를 반환하면 JPA는 SELECT 없이 바로 INSERT한다.

### 연관관계 매핑

```kotlin
@Entity
class Order(
    @Id val id: UUID = UUID.randomUUID(),

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "user_id")
    var user: User? = null  // nullable로 선언 (프록시 대응)
) {
    @OneToMany(mappedBy = "order", cascade = [CascadeType.ALL])
    val items: MutableList<OrderItem> = mutableListOf()

    fun addItem(item: OrderItem) {
        items.add(item)
        item.order = this  // 양방향 동기화
    }
}
```

### 엔티티 템플릿

```kotlin
@Entity
@Table(name = "vehicles")
class Vehicle(
    @Id
    @Column(length = 36)
    val id: UUID = UUID.randomUUID(),

    @Column(nullable = false, length = 100)
    var name: String,

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)
    var status: VehicleStatus = VehicleStatus.ACTIVE

) : Persistable<UUID> {

    @CreatedDate
    @Column(updatable = false)
    var createdAt: Instant? = null

    @LastModifiedDate
    var updatedAt: Instant? = null

    override fun getId(): UUID = id
    override fun isNew(): Boolean = createdAt == null

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other == null || Hibernate.getClass(this) != Hibernate.getClass(other)) return false
        other as Vehicle
        return id == other.id
    }

    override fun hashCode(): Int = javaClass.hashCode()
}
```

---

## QueryDSL

```kotlin
// build.gradle.kts
plugins {
    kotlin("kapt")
}

dependencies {
    implementation("com.querydsl:querydsl-jpa:5.0.0:jakarta")
    kapt("com.querydsl:querydsl-apt:5.0.0:jakarta")
}
```

### Repository 예시

```kotlin
@Repository
class VehicleRepositoryImpl(
    private val queryFactory: JPAQueryFactory
) : VehicleRepositoryCustom {

    override fun findByCondition(condition: VehicleSearchCondition): List<Vehicle> {
        val vehicle = QVehicle.vehicle

        return queryFactory
            .selectFrom(vehicle)
            .where(
                vehicle.status.eq(condition.status),
                condition.name?.let { vehicle.name.containsIgnoreCase(it) }
            )
            .orderBy(vehicle.createdAt.desc())
            .fetch()
    }
}
```

**Kotlin null safety 활용:**
```kotlin
// 조건이 null이면 where 절에서 제외
condition.name?.let { vehicle.name.containsIgnoreCase(it) }
```

---

## Profile 전략

```kotlin
@Configuration
@Profile("dev")
class DevConfig {
    @Bean
    fun dataSource() = EmbeddedDatabaseBuilder()...
}

@Configuration
@Profile("prod")
class ProdConfig {
    @Bean
    fun dataSource() = HikariDataSource(...)
}
```

### 활성화

```yaml
spring:
  profiles:
    active: dev
    include:
      - common
      - cache
```

### 환경별 구성

| 환경 | 용도 | 주요 설정 |
|------|------|----------|
| local | 개발 | H2, Mock 어댑터 |
| integration | 통합 테스트 | Testcontainers |
| prod | 프로덕션 | 실제 인프라 |

---

## @Configuration vs @Component

```kotlin
@Configuration
class AppConfig {
    @Bean
    fun serviceA(): ServiceA = ServiceA(serviceB())

    @Bean
    fun serviceB(): ServiceB = ServiceB()
}
```

`@Configuration`은 **CGLIB 프록시**로 감싸서 `serviceB()`를 여러 번 호출해도 **같은 인스턴스**를 반환한다.

`@Component`는 프록시가 없어서 호출할 때마다 새 인스턴스가 생성된다.

---

## Spring WebFlux

### Reactive vs Servlet

| 기준 | Servlet (Spring MVC) | Reactive (WebFlux) |
|------|---------------------|-------------------|
| 스레드 모델 | Thread per Request | Event Loop |
| 블로킹 | 허용 | 금지 |
| 적합한 상황 | CPU 집약적, 동기 DB | I/O 집약적, 많은 동시 연결 |
| 런타임 | Tomcat | Netty |

### Mono vs Flux

```kotlin
// Mono: 0 또는 1개 요소
Mono.just("Hello")
Mono.empty()

// Flux: 0개 이상 요소
Flux.just("A", "B", "C")
Flux.fromIterable(list)
```

### 주의사항

```kotlin
// ❌ 블로킹 호출 금지
@GetMapping("/users")
fun getUsers(): Flux<User> {
    val users = userRepository.findAll()  // 블로킹!
    return Flux.fromIterable(users)
}

// ✅ 리액티브 리포지토리 사용
@GetMapping("/users")
fun getUsers(): Flux<User> {
    return reactiveUserRepository.findAll()
}
```

---

## Kotlin Coroutine + Spring

### suspend 함수

```kotlin
@GetMapping("/user/{id}")
suspend fun getUser(@PathVariable id: String): User {
    return userService.findById(id)  // suspend 함수
}
```

### Flow

```kotlin
@GetMapping("/users", produces = [MediaType.APPLICATION_NDJSON_VALUE])
fun getUsers(): Flow<User> {
    return userService.findAll()  // Flow 반환
}
```

### Coroutine Context

```kotlin
@Service
class UserService(
    private val userRepository: UserRepository
) {
    suspend fun findById(id: String): User = withContext(Dispatchers.IO) {
        userRepository.findById(id)  // 블로킹 호출을 IO 스레드에서
    }
}
```

---

## Spring Security

### 인증 흐름

```
Request → AuthenticationFilter → AuthenticationManager
                                       ↓
                              AuthenticationProvider
                                       ↓
                                 UserDetailsService
                                       ↓
                              UserDetails (DB 조회)
                                       ↓
                              Authentication 객체 생성
                                       ↓
                              SecurityContextHolder에 저장
```

### JWT 인증

```kotlin
@Component
class JwtAuthenticationFilter(
    private val jwtProvider: JwtProvider
) : OncePerRequestFilter() {

    override fun doFilterInternal(
        request: HttpServletRequest,
        response: HttpServletResponse,
        filterChain: FilterChain
    ) {
        val token = extractToken(request)
        if (token != null && jwtProvider.validate(token)) {
            val authentication = jwtProvider.getAuthentication(token)
            SecurityContextHolder.getContext().authentication = authentication
        }
        filterChain.doFilter(request, response)
    }
}
```

### Method Security

```kotlin
@EnableMethodSecurity
@Configuration
class SecurityConfig

@Service
class OrderService {
    @PreAuthorize("hasRole('ADMIN')")
    fun deleteOrder(id: String) { }

    @PreAuthorize("#userId == authentication.principal.id")
    fun getOrders(userId: String): List<Order> { }
}
```

---

## Spring Batch

### 구성요소

```
Job
 └── Step
      ├── Reader (ItemReader)
      ├── Processor (ItemProcessor)
      └── Writer (ItemWriter)
```

### Chunk 기반 처리

```kotlin
@Bean
fun orderProcessingStep(
    jobRepository: JobRepository,
    transactionManager: PlatformTransactionManager
): Step {
    return StepBuilder("orderProcessingStep", jobRepository)
        .chunk<Order, ProcessedOrder>(100, transactionManager)
        .reader(orderReader())
        .processor(orderProcessor())
        .writer(processedOrderWriter())
        .build()
}
```

### 재시작과 멱등성

```kotlin
@Bean
fun job(jobRepository: JobRepository, step: Step): Job {
    return JobBuilder("orderJob", jobRepository)
        .incrementer(RunIdIncrementer())  // 매번 새 인스턴스
        .start(step)
        .build()
}
```

---

## Spring Data JPA Kotlin 확장

```kotlin
// CrudRepositoryExtensions
val vehicle: Vehicle = repository.findByIdOrNull(id)
    ?: throw NotFoundException("Vehicle not found: $id")

// 기존 Java 스타일
val vehicle: Vehicle = repository.findById(id)
    .orElseThrow { NotFoundException("Vehicle not found: $id") }
```

`findByIdOrNull`이 더 Kotlin스럽다.

---

## 관련 Interview 문서

- [14-kotlin-jpa.md](../interview/14-kotlin-jpa.md)
- [15-spring-core.md](../interview/15-spring-core.md)

---

*다음: [07-infrastructure.md](./07-infrastructure.md)*
