# 아키텍처 패턴

## DDD (Domain-Driven Design)

### 전략적 설계

| 개념 | 설명 |
|------|------|
| **Bounded Context** | 도메인 모델의 경계 (하나의 마이크로서비스) |
| **Ubiquitous Language** | 개발자-도메인 전문가 공통 언어 |
| **Context Map** | Bounded Context 간 관계 |

### Context Map 패턴

```
┌─────────────┐      ┌─────────────┐
│   주문 BC   │ ───▶ │   결제 BC   │
│  (Upstream) │ ACL  │ (Downstream)│
└─────────────┘      └─────────────┘
```

| 패턴 | 설명 | 예시 |
|------|------|------|
| **Shared Kernel** | 공유 모델 | 공통 라이브러리 |
| **Customer-Supplier** | 상하류 관계 | 팀 간 API 계약 |
| **Anti-Corruption Layer** | 외부 모델 변환 | 레거시 연동 |
| **Open Host Service** | 표준 API 제공 | 공개 API |
| **Published Language** | 표준 교환 형식 | JSON Schema |

### 전술적 설계

| 빌딩블록 | 역할 | 예시 |
|----------|------|------|
| **Entity** | 식별자가 있는 객체 | User, Order |
| **Value Object** | 불변, 값으로 비교 | Money, Address |
| **Aggregate** | 일관성 경계 | Order + OrderItems |
| **Aggregate Root** | Aggregate 진입점 | Order |
| **Domain Event** | 도메인 내 발생 사건 | OrderPlaced |
| **Repository** | Aggregate 저장소 | OrderRepository |
| **Domain Service** | 엔티티에 속하지 않는 로직 | TransferService |

### Aggregate 설계 원칙

```kotlin
// ✅ 좋은 예: Aggregate Root를 통해서만 접근
class Order(val id: OrderId) {
    private val items: MutableList<OrderItem> = mutableListOf()

    fun addItem(product: Product, quantity: Int) {
        // 불변식 검증
        require(items.size < 100) { "주문 항목은 100개 이하" }
        items.add(OrderItem(product, quantity))
    }
}

// ❌ 나쁜 예: 직접 OrderItem 수정
orderItem.quantity = 5  // Aggregate 우회
```

**원칙:**
1. 외부에서 Aggregate Root만 참조
2. 트랜잭션 = 하나의 Aggregate
3. Aggregate 간 참조는 ID로만

---

## Event-Driven Architecture

### 이벤트 종류

| 유형 | 설명 | 예시 |
|------|------|------|
| **Domain Event** | 비즈니스 사건 | OrderPlaced |
| **Integration Event** | 서비스 간 통신 | OrderPlacedIntegrationEvent |
| **Notification Event** | 최소 정보만 | { type: "order_placed", id: 123 } |

### Event Sourcing

모든 상태 변경을 이벤트로 저장.

```kotlin
// 상태 변경 대신 이벤트 저장
class OrderAggregate {
    private val events = mutableListOf<Event>()

    fun place() {
        applyEvent(OrderPlaced(orderId, items))
    }

    fun cancel() {
        applyEvent(OrderCancelled(orderId))
    }
}

// 이벤트 스토어
[
  { type: "OrderPlaced", orderId: 1, items: [...] },
  { type: "ItemAdded", orderId: 1, item: {...} },
  { type: "OrderCancelled", orderId: 1 }
]

// 현재 상태 = 이벤트 리플레이
```

### Event Sourcing 장단점

| 장점 | 단점 |
|------|------|
| 완전한 감사 로그 | 복잡한 구현 |
| 시간 여행 (특정 시점 복원) | 이벤트 스키마 진화 어려움 |
| 디버깅 용이 | 쿼리 복잡 (CQRS 필요) |

### CQRS (Command Query Responsibility Segregation)

```
           ┌──────────────┐
Command ──▶│  Write Model │──▶ Event Store
           └──────────────┘
                  │
                  ▼ (Event)
           ┌──────────────┐
Query ◀────│  Read Model  │◀── Projection
           └──────────────┘
```

**Write Model**: 비즈니스 로직, 정규화
**Read Model**: 조회 최적화, 비정규화

```kotlin
// Write: Event 발행
fun placeOrder(command: PlaceOrderCommand) {
    val order = Order.create(command)
    eventStore.append(OrderPlaced(order.id, order.items))
}

// Read: Projection (비동기 업데이트)
@EventHandler
fun on(event: OrderPlaced) {
    orderSummaryRepository.save(
        OrderSummary(event.orderId, event.items.size, event.total)
    )
}
```

---

## Saga Pattern

### Choreography vs Orchestration

```
Choreography (이벤트 기반):

Order ──▶ Payment ──▶ Inventory ──▶ Shipping
       event     event        event

Orchestration (중앙 조정자):

        ┌─────────────┐
        │    Saga     │
        │ Orchestrator│
        └──────┬──────┘
     ┌─────────┼─────────┐
     ▼         ▼         ▼
  Payment  Inventory  Shipping
```

| 방식 | 장점 | 단점 |
|------|------|------|
| **Choreography** | 느슨한 결합, 단순 | 흐름 파악 어려움, 순환 위험 |
| **Orchestration** | 명확한 흐름, 테스트 용이 | 중앙 집중, 단일 장애점 |

### 보상 트랜잭션

```kotlin
class CreateOrderSaga(
    private val paymentService: PaymentService,
    private val inventoryService: InventoryService
) {
    fun execute(order: Order) {
        try {
            // Forward
            val paymentId = paymentService.charge(order.total)
            val reservationId = inventoryService.reserve(order.items)

        } catch (e: Exception) {
            // Compensate (역순)
            inventoryService.cancelReservation(reservationId)
            paymentService.refund(paymentId)
            throw e
        }
    }
}
```

### Saga 상태 관리

```kotlin
enum class SagaState {
    STARTED,
    PAYMENT_COMPLETED,
    INVENTORY_RESERVED,
    COMPLETED,
    COMPENSATING,
    COMPENSATED,
    FAILED
}

@Entity
class OrderSaga(
    @Id val sagaId: String,
    var state: SagaState,
    var paymentId: String?,
    var reservationId: String?
)
```

---

## API Gateway Pattern

### 역할

```
Client ──▶ API Gateway ──▶ Service A
                      ──▶ Service B
                      ──▶ Service C
```

| 기능 | 설명 |
|------|------|
| **라우팅** | 요청을 적절한 서비스로 |
| **인증/인가** | JWT 검증, API Key |
| **Rate Limiting** | 요청 제한 |
| **로드 밸런싱** | 트래픽 분산 |
| **API Composition** | 여러 서비스 응답 조합 |
| **캐싱** | 응답 캐시 |

### BFF (Backend for Frontend)

```
Mobile App ──▶ Mobile BFF ──┐
Web App ────▶ Web BFF ──────┼──▶ Internal Services
Partner ────▶ Partner API ──┘
```

각 클라이언트 특성에 맞는 API 제공.

---

## Service Mesh

### Sidecar Pattern

```
┌─────────────────────────────┐
│         Pod                 │
│ ┌─────────┐  ┌───────────┐ │
│ │ Service │◀▶│  Sidecar  │ │
│ │  (App)  │  │  (Envoy)  │ │
│ └─────────┘  └───────────┘ │
└─────────────────────────────┘
```

### Istio 구성

| 구성요소 | 역할 |
|----------|------|
| **Envoy** | Sidecar 프록시 |
| **Istiod** | 컨트롤 플레인 (설정 배포) |
| **Kiali** | 시각화 |
| **Jaeger** | 분산 트레이싱 |

### 주요 기능

```yaml
# 트래픽 분할 (카나리 배포)
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
spec:
  http:
    - route:
        - destination:
            host: my-service
            subset: v1
          weight: 90
        - destination:
            host: my-service
            subset: v2
          weight: 10
```

| 기능 | 설명 |
|------|------|
| mTLS | 서비스 간 암호화 통신 |
| Retry/Timeout | 자동 재시도 |
| Circuit Breaker | 장애 격리 |
| Observability | 메트릭, 트레이싱, 로깅 |

---

## Strangler Fig Pattern

레거시 시스템 점진적 교체.

```
Phase 1: Proxy만 추가
┌────────────┐    ┌────────────┐
│   Proxy    │───▶│   Legacy   │
└────────────┘    └────────────┘

Phase 2: 일부 기능 교체
┌────────────┐    ┌────────────┐
│   Proxy    │───▶│ New Service│
│            │───▶│   Legacy   │
└────────────┘    └────────────┘

Phase 3: 완전 교체
┌────────────┐    ┌────────────┐
│   Proxy    │───▶│ New Service│
└────────────┘    └────────────┘
```

### 적용 전략

| 단계 | 설명 |
|------|------|
| **Intercept** | 프록시 레이어 추가 |
| **Identify** | 교체할 기능 선별 |
| **Transform** | 새 서비스 구현 |
| **Redirect** | 트래픽 전환 |
| **Retire** | 레거시 제거 |

---

## Hexagonal Architecture

### 정의

Alistair Cockburn이 정의한 **Port & Adapter** 패턴.

### 구조

```
              [Web Controller]
                    │
                    ▼
          ┌─────────────────────┐
          │     Port (In)       │  ← UseCase 인터페이스
          ├─────────────────────┤
          │                     │
          │    Domain Core      │  ← 순수 비즈니스 로직
          │                     │
          ├─────────────────────┤
          │     Port (Out)      │  ← Repository 인터페이스
          └─────────────────────┘
                    │
                    ▼
           [JPA Repository]
```

### Port & Adapter

| 개념 | 역할 | 예시 |
|------|------|------|
| **Inbound Port** | 외부 → 내부 계약 | UseCase 인터페이스 |
| **Outbound Port** | 내부 → 외부 계약 | Repository 인터페이스 |
| **Inbound Adapter** | Inbound Port 구현 | Controller, Consumer |
| **Outbound Adapter** | Outbound Port 구현 | JPA Repository, API Client |

### 코드 예시

```kotlin
// Inbound Port
interface RegisterVehicleUseCase {
    fun execute(command: RegisterVehicleCommand): Vehicle
}

// Outbound Port
interface VehicleRepository {
    fun save(vehicle: Vehicle): Vehicle
    fun findById(id: String): Vehicle?
}

// Inbound Adapter
@RestController
class VehicleController(
    private val registerVehicle: RegisterVehicleUseCase
) {
    @PostMapping("/vehicles")
    fun register(@RequestBody request: RegisterRequest) =
        registerVehicle.execute(request.toCommand())
}

// Outbound Adapter
@Repository
class JpaVehicleRepository(
    private val jpaRepository: VehicleJpaRepository
) : VehicleRepository {
    override fun save(vehicle: Vehicle) =
        jpaRepository.save(vehicle.toEntity()).toDomain()
}
```

### Layered vs Hexagonal

| 기준 | Layered | Hexagonal |
|------|---------|-----------|
| 의존성 방향 | 위 → 아래 | 바깥 → 안쪽 |
| 도메인 순수성 | 인프라 의존 가능 | 순수 (인프라 무관) |
| 테스트 용이성 | 낮음 | 높음 |
| 어댑터 교체 | 어려움 | 쉬움 |

---

## Clean Architecture

### 구조

```
┌─────────────────────────────────────────┐
│           Frameworks & Drivers          │  ← 프레임워크
├─────────────────────────────────────────┤
│        Interface Adapters               │  ← 어댑터
├─────────────────────────────────────────┤
│          Use Cases                      │  ← 애플리케이션 로직
├─────────────────────────────────────────┤
│           Entities                      │  ← 도메인
└─────────────────────────────────────────┘
```

### Hexagonal vs Clean

| 기준 | Hexagonal | Clean |
|------|-----------|-------|
| 계층 수 | 3 | 4 |
| 복잡도 | 중간 | 높음 |
| 의존성 규칙 | Port 기반 | 계층 기반 |
| 실무 적합 | 높음 | 중간 |

---

## 멀티모듈 구조

### 디렉토리

```
project/
├── app-api/              # API 서버 (Inbound Adapter)
├── app-consumer/         # Kafka 컨슈머 (Inbound Adapter)
├── adapter-persistence/  # DB 어댑터 (Outbound Adapter)
├── adapter-kafka/        # Kafka 어댑터 (Outbound Adapter)
├── application/          # UseCase, Port
└── domain/               # 순수 도메인 로직
```

### 의존성 방향

```
app-api ─────────────────────────┐
app-consumer ────────────────────┼──▶ application ──▶ domain
adapter-persistence ─────────────┤
adapter-kafka ───────────────────┘
```

### 모듈별 의존성

```kotlin
// domain (의존성 없음)
dependencies { }

// application
dependencies {
    implementation(project(":domain"))
}

// adapter-persistence
dependencies {
    implementation(project(":application"))
    implementation(project(":domain"))
    implementation("spring-boot-starter-data-jpa")
}

// app-api
dependencies {
    implementation(project(":application"))
    implementation(project(":adapter-persistence"))
    implementation(project(":adapter-kafka"))
}
```

### api vs implementation

| 구분 | api | implementation |
|------|-----|----------------|
| 전이 의존성 | 노출 | 숨겨짐 |
| 재컴파일 범위 | 하위 포함 | 해당 모듈만 |
| 사용 시점 | 인터페이스 노출 | 내부 구현 |

---

## RBAC vs ReBAC

### RBAC (Role-Based Access Control)

```
사용자 → 역할(Admin, Editor) → 권한(Read, Write)
```

| 장점 | 단점 |
|------|------|
| 구현 단순 | 계층 구조 표현 어려움 |
| 성능 좋음 | 유연성 낮음 |
| 이해 쉬움 | 복잡한 관계 불가 |

### ReBAC (Relationship-Based Access Control)

```
alice는 folder:docs의 owner다
folder:docs는 file:report.pdf의 parent다
→ alice는 file:report.pdf를 read할 수 있다
```

| 장점 | 단점 |
|------|------|
| 계층 구조 자연스러움 | 구현 복잡 |
| 매우 유연 | 학습 곡선 |
| Google Drive 같은 구조 | 성능 고려 필요 |

### OpenFGA 스키마 예시

```fga
model
  schema 1.1

type user

type folder
  relations
    define owner: [user]
    define viewer: [user] or owner
    define parent: [folder]
    define can_read: viewer or can_read from parent
```

### 선택 기준

| 상황 | 선택 |
|------|------|
| 단순 역할 (Admin/User) | RBAC |
| 계층 리소스 (폴더/파일) | ReBAC |
| 조직 구조 | ReBAC |
| 빠른 구현 필요 | RBAC |

---

## Rate Limiting 알고리즘

### 알고리즘 비교

| 알고리즘 | Burst | 메모리 | 정확도 |
|----------|-------|--------|--------|
| **Token Bucket** | O | O(1) | 높음 |
| **Leaky Bucket** | X | O(N) | 높음 |
| **Fixed Window** | 경계 2배 | O(1) | 낮음 |
| **Sliding Window Log** | X | O(N) | 매우 높음 |
| **Sliding Window Counter** | 일부 | O(1) | 높음 |

### Token Bucket

```
1. 버킷에 일정 속도로 토큰 추가 (초당 10개)
2. 요청 시 토큰 1개 소비
3. 토큰 없으면 거부
4. 버킷 용량 초과 시 버려짐 (burst 제한)
```

```kotlin
class TokenBucket(
    private val capacity: Long,
    private val refillRate: Long
) {
    private var tokens: Double = capacity.toDouble()
    private var lastRefillTime: Long = System.nanoTime()

    @Synchronized
    fun tryConsume(): Boolean {
        refill()
        return if (tokens >= 1) {
            tokens -= 1
            true
        } else false
    }
}
```

### Fixed Window 경계 문제

```
     윈도우 1         윈도우 2
|---------|---------|
          ↑
      경계 시점

윈도우 1 마지막 1초: 100 요청
윈도우 2 처음 1초: 100 요청
→ 2초 동안 200 요청 (제한의 2배!)
```

### 분산 환경 (Redis + Lua)

```lua
local tokens = tonumber(redis.call('HGET', key, 'tokens')) or capacity
local last_refill = tonumber(redis.call('HGET', key, 'last_refill')) or now

-- 토큰 리필
local elapsed = now - last_refill
tokens = math.min(capacity, tokens + elapsed * refill_rate)

-- 토큰 소비
if tokens >= 1 then
    tokens = tokens - 1
    redis.call('HMSET', key, 'tokens', tokens, 'last_refill', now)
    return 1
else
    return 0
end
```

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

```
인프라 (AutoConfiguration) → 암묵적 (Spring Boot가 처리)
비즈니스 (@Import) → 명시적 (개발자가 관리)
```

---

## 관련 Interview 문서

- [07-openfga-rebac.md](../interview/07-openfga-rebac.md)
- [08-rate-limiting.md](../interview/08-rate-limiting.md)
- [12-hexagonal.md](../interview/12-hexagonal.md)
- [13-multi-module.md](../interview/13-multi-module.md)

---

*다음: [06-spring-kotlin.md](./06-spring-kotlin.md)*
