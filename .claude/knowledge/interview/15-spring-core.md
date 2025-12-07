# Spring 핵심 개념

## 이력서 연결

> "Kotlin, Java, Spring Boot, JPA, QueryDSL"
> "Hexagonal Architecture 기반 서비스 설계"
> "@Import 기반 명시적 빈 구성"

---

## 핵심 답변 (STAR)

### Situation (상황)
- 42dot Vehicle Platform, Spring Boot + Kotlin
- 멀티모듈 프로젝트에서 어떤 빈이 등록되는지 파악 어려움
- 테스트 시 Context 재사용 문제

### Task (과제)
- 명시적인 의존성 관리
- 테스트 환경과 프로덕션 환경의 일관성
- Spring Boot의 Convention과 명시적 설정의 균형

### Action (행동)
1. **@Import 기반 빈 구성**
   - `@ComponentScan` 대신 `@Import`로 명시적 등록
   - 어떤 어댑터가 활성화되는지 코드에서 파악 가능

2. **Config 클래스 분리**
   - 어댑터별 Config 분리
   - 테스트에서 필요한 Config만 Import

3. **Profile 전략**
   - 환경별 Config 활성화
   - `profiles.include`로 Config 조합

### Result (결과)
- 의존성이 코드에서 명확히 보임
- 테스트 Context 재사용으로 빌드 시간 단축
- 새 팀원 온보딩 시간 단축

---

## 예상 질문

### Q1: @ComponentScan 대신 @Import를 사용한 이유는?

**답변:**
`@ComponentScan`은 패키지 전체를 스캔하여 **암묵적**으로 빈을 등록한다.

**문제점:**
1. 어떤 빈이 등록되는지 코드에서 보이지 않음
2. 원치 않는 빈이 등록될 수 있음
3. 멀티 모듈에서 혼란

**해결: @Import로 명시적 등록**
```kotlin
@EnableAutoConfiguration  // 인프라는 자동
@Import(
    WebAdapterConfig::class,
    PersistenceAdapterConfig::class,
    ClientAdapterConfig::class,
    CacheAdapterConfig::class,
    UseCaseConfig::class,
)
class UserPlatformApiApplication
```

**경계 정의:**
| 구분 | 설정 방식 | 예시 |
|------|----------|------|
| 인프라 | AutoConfiguration (암묵적) | DataSource, JPA, Kafka |
| 비즈니스 | @Import (명시적) | Controller, Adapter, UseCase |

애플리케이션 클래스만 보면 어떤 어댑터가 활성화되는지 즉시 파악 가능하다.

### Q2: Spring Bean의 생명주기를 설명해주세요

**답변:**

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

**실무 예시:**
```kotlin
@Component
class CacheWarmer(
    private val cache: CacheManager
) {
    @PostConstruct
    fun warmUp() {
        // 자주 사용되는 데이터 미리 캐싱
        cache.loadHotData()
    }

    @PreDestroy
    fun cleanup() {
        // 리소스 정리
        cache.flush()
    }
}
```

### Q3: IoC/DI를 설명해주세요

**답변:**

**IoC (Inversion of Control):**
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

**DI (Dependency Injection):**
의존성을 외부에서 주입받는 패턴이다.

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

**생성자 주입이 권장되는 이유:**
- 불변성 보장 (val 사용 가능)
- 필수 의존성 명확
- 테스트 용이 (Mock 주입 쉬움)
- 순환 의존성 컴파일 타임에 감지

### Q4: @Transactional의 동작 원리는?

**답변:**
Spring AOP 기반으로 **프록시 패턴**을 사용한다.

```kotlin
@Service
class OrderService(
    private val orderRepository: OrderRepository
) {
    @Transactional
    fun createOrder(request: CreateOrderRequest): Order {
        val order = Order(request)
        return orderRepository.save(order)
    }
}
```

**내부 동작:**
```
Client → Proxy → Target (OrderService)
           │
           ├─ 트랜잭션 시작 (BEGIN)
           │
           ├─ 실제 메서드 실행
           │
           └─ 트랜잭션 종료 (COMMIT/ROLLBACK)
```

**주의점:**

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
        // ...
        internalMethod()  // ❌ 트랜잭션 미적용 (내부 호출)
    }

    @Transactional
    fun internalMethod() { }
}
```

**해결책:**
- 별도 클래스로 분리
- `self.internalMethod()` 패턴
- AspectJ 모드 사용

### Q5: Spring AOP를 설명해주세요

**답변:**
**관점 지향 프로그래밍**으로 횡단 관심사를 분리한다.

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

// 사용
@Loggable
fun processOrder(order: Order) { ... }
```

**주요 개념:**
| 용어 | 설명 |
|------|------|
| Aspect | 횡단 관심사 모듈 |
| Advice | 실제 수행될 로직 (Before, After, Around) |
| Pointcut | 어디에 적용할지 정의 |
| JoinPoint | 메서드 실행 시점 |

**Spring AOP vs AspectJ:**
| 기준 | Spring AOP | AspectJ |
|------|-----------|---------|
| 방식 | 프록시 기반 | 바이트코드 조작 |
| 성능 | 약간 느림 | 빠름 |
| 적용 범위 | public 메서드만 | 모든 곳 |
| 설정 | 간단 | 복잡 |

---

## 꼬리 질문 대비

### Q: Bean Scope는 어떤 것이 있나요?

**답변:**

| Scope | 설명 | 사용 시점 |
|-------|------|----------|
| singleton | 기본값, 앱에 하나 | 대부분 |
| prototype | 요청마다 새로 생성 | 상태 있는 빈 |
| request | HTTP 요청마다 | 웹 |
| session | HTTP 세션마다 | 웹 |

```kotlin
@Component
@Scope("prototype")
class RequestContext {
    var userId: String? = null
}
```

### Q: @Configuration과 @Component 차이는?

**답변:**

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

### Q: Profile은 어떻게 활용하나요?

**답변:**

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

**활성화 방법:**
```yaml
# application.yml
spring:
  profiles:
    active: dev
    include:
      - common
      - cache
```

**우리 프로젝트에서:**
- `local`: 개발용 (H2, Mock 어댑터)
- `integration`: 통합 테스트 (Testcontainers)
- `prod`: 프로덕션

### Q: Spring Boot 자동 설정을 비활성화하려면?

**답변:**

```kotlin
@SpringBootApplication(
    exclude = [
        DataSourceAutoConfiguration::class,
        SecurityAutoConfiguration::class
    ]
)
class MyApplication
```

또는 `application.yml`:
```yaml
spring:
  autoconfigure:
    exclude:
      - org.springframework.boot.autoconfigure.security.servlet.SecurityAutoConfiguration
```

---

## 관련 개념 정리

| 개념 | 설명 |
|------|------|
| IoC | 제어의 역전, 객체 생성을 프레임워크에 위임 |
| DI | 의존성 주입, 외부에서 의존 객체 주입 |
| AOP | 관점 지향 프로그래밍, 횡단 관심사 분리 |
| Bean Scope | 빈의 생명주기 범위 |
| Profile | 환경별 설정 분리 |
| @Configuration | CGLIB 프록시 적용 설정 클래스 |
| @Transactional | 선언적 트랜잭션 관리 |
| ApplicationContext | Spring IoC 컨테이너 |

---

## 블로그 링크

- [Selectively Opinionated Spring Boot (1) - @ComponentScan의 함정](https://gyeom.github.io/dev-notes/posts/2024-03-15-spring-component-scan-philosophy-part1/)
- [Selectively Opinionated Spring Boot (2) - 멀티앱, 하나의 코드베이스](https://gyeom.github.io/dev-notes/posts/2024-03-18-spring-component-scan-philosophy-part2/)
- [Selectively Opinionated Spring Boot (3) - Mock 남용 없는 통합 테스트](https://gyeom.github.io/dev-notes/posts/2024-03-22-spring-component-scan-philosophy-part3/)

---

*다음: [16-observability.md](./16-observability.md)*
