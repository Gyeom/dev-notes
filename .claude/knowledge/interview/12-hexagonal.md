# Hexagonal Architecture

## 이력서 연결

> "Hexagonal Architecture(Port & Adapter) 기반 설계"
> "인프라와 비즈니스 로직의 명확한 분리"

---

## 핵심 답변 (STAR)

### Situation (상황)
- 42dot Vehicle Platform, 마이크로서비스 아키텍처
- DB, Kafka, 외부 API 등 다양한 인프라 연동
- 기존 레이어드 아키텍처에서 인프라 변경 시 도메인 코드도 수정 필요

### Task (과제)
- 인프라와 비즈니스 로직 분리
- 테스트 용이성 확보
- 어댑터 교체 가능한 구조

### Action (행동)
1. **Port & Adapter 구조 적용**
   - Port: 인터페이스 정의 (UseCase, Repository)
   - Adapter: 구현체 (Controller, JPA Repository, API Client)

2. **@Import 기반 명시적 빈 구성**
   - `@ComponentScan` 대신 `@Import`로 명확한 의존성
   - 각 Adapter Config 명시적 등록

3. **테스트 Mock 어댑터**
   - 외부 API용 Mock 어댑터 구현
   - `@Primary`로 테스트 시 교체

### Result (결과)
- 인프라 변경이 도메인에 영향 없음
- 테스트 작성 용이
- 어떤 어댑터가 활성화되는지 코드에서 명확히 파악

---

## 예상 질문

### Q1: Hexagonal Architecture가 뭔가요?

**답변:**
Alistair Cockburn이 정의한 아키텍처 패턴으로, **Port & Adapter** 패턴이라고도 한다.

핵심 아이디어:
- 애플리케이션 코어(도메인 로직)를 중심에 두고
- 외부 세계와의 통신은 Port(인터페이스)를 통해
- 실제 구현은 Adapter가 담당

```
              [Web Controller]
                    │
                    ▼
          ┌─────────────────────┐
          │     Port (In)       │
          │    (UseCase)        │
          ├─────────────────────┤
          │                     │
          │    Domain Core      │
          │  (Business Logic)   │
          │                     │
          ├─────────────────────┤
          │     Port (Out)      │
          │  (Repository)       │
          └─────────────────────┘
                    │
                    ▼
           [JPA Repository]
```

**장점:**
- 도메인 로직이 인프라에 의존하지 않음
- 테스트 시 Adapter만 교체 가능
- 인프라 변경이 도메인에 영향 없음

### Q2: Port와 Adapter의 차이는?

**답변:**

**Port (인터페이스):**
- 비즈니스 로직이 외부와 통신하는 계약
- Inbound Port: 외부 → 내부 (UseCase)
- Outbound Port: 내부 → 외부 (Repository, Client)

```kotlin
// Inbound Port (UseCase)
interface RegisterVehicleUseCase {
    fun execute(command: RegisterVehicleCommand): Vehicle
}

// Outbound Port
interface VehicleRepository {
    fun save(vehicle: Vehicle): Vehicle
    fun findById(id: String): Vehicle?
}
```

**Adapter (구현체):**
- Port의 실제 구현
- 특정 기술에 의존 (JPA, Kafka, HTTP 등)

```kotlin
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
    override fun save(vehicle: Vehicle) = jpaRepository.save(vehicle.toEntity()).toDomain()
}
```

### Q3: @ComponentScan 대신 @Import를 사용한 이유는?

**답변:**
`@ComponentScan`은 패키지 전체를 스캔하여 **암묵적**으로 빈을 등록한다.

**문제점:**
1. 어떤 빈이 등록되는지 코드에서 보이지 않음
2. 원치 않는 빈이 등록될 수 있음
3. 멀티 모듈에서 혼란

**해결: @Import로 명시적 등록**
```kotlin
@EnableAutoConfiguration
@Import(
    WebAdapterConfig::class,
    PersistenceAdapterConfig::class,
    ClientAdapterConfig::class,
    CacheAdapterConfig::class,
    UseCaseConfig::class,
)
class UserPlatformApiApplication
```

**장점:**
- 애플리케이션 클래스만 보면 어떤 어댑터가 활성화되는지 파악
- 인프라는 AutoConfiguration (암묵적)
- 비즈니스는 @Import (명시적)

### Q4: 테스트에서 어떻게 활용했나요?

**답변:**
**외부 API만 Mock, 내부 인프라는 실제 사용**

```kotlin
@Component("vdpServiceAdapter")
@Primary  // 테스트에서 우선 선택
class TestVdpServiceAdapter : VdpOut {
    private val store = mutableMapOf<String, VdpDeviceInfo>()

    override fun registerDevice(deviceSourceId: String): VdpDeviceInfo {
        return store.getOrPut(deviceSourceId) {
            VdpDeviceInfo(deviceId = UUID.randomUUID())
        }
    }
}
```

Port 인터페이스를 통해 Adapter를 쉽게 교체할 수 있다. Hexagonal Architecture의 핵심 이점이다.

Alistair Cockburn 원문:
> "Allow an application to equally be driven by users, programs, automated test or batch scripts"

### Q5: 레이어드 아키텍처와 차이점은?

**답변:**

**Layered Architecture:**
```
Presentation → Business → Data Access → Database
```
- 상위 레이어가 하위 레이어에 의존
- Data Access가 DB 기술에 의존

**Hexagonal Architecture:**
```
[Adapter] → [Port] → [Domain] ← [Port] ← [Adapter]
```
- 도메인이 중심
- 모든 의존성이 안쪽(도메인)을 향함
- 인프라가 도메인에 의존

**차이:**
| 기준 | Layered | Hexagonal |
|------|---------|-----------|
| 의존성 방향 | 위 → 아래 | 바깥 → 안쪽 |
| 도메인 순수성 | 인프라에 의존 가능 | 순수 (인프라 무관) |
| 테스트 용이성 | 낮음 | 높음 |
| 어댑터 교체 | 어려움 | 쉬움 |

---

## 꼬리 질문 대비

### Q: 인바운드/아웃바운드 구분은?

**답변:**

**Inbound (Driving):**
- 외부에서 애플리케이션을 "구동"
- Controller, Consumer, Scheduler
- UseCase(Inbound Port)를 호출

**Outbound (Driven):**
- 애플리케이션이 외부를 "사용"
- Repository, API Client, Producer
- 도메인이 Outbound Port를 호출 → Adapter가 구현

```
[Web Controller]  →  UseCase(Port)  →  Domain
      (In)                              │
                                        │
                     Repository(Port) ← ┘
                           │
                    [JPA Adapter]
                        (Out)
```

### Q: 도메인 로직은 어디에 있나요?

**답변:**
두 가지 선택지:

1. **Rich Domain Model**: 도메인 엔티티 내부에 비즈니스 로직
   ```kotlin
   class Vehicle {
       fun activate() {
           require(status == INACTIVE) { "Already active" }
           status = ACTIVE
           registerEvent(VehicleActivated(id))
       }
   }
   ```

2. **UseCase**: 애플리케이션 서비스에 비즈니스 로직
   ```kotlin
   class ActivateVehicleUseCase(
       private val vehicleRepository: VehicleRepository
   ) {
       fun execute(vehicleId: String) {
           val vehicle = vehicleRepository.findById(vehicleId)
           vehicle.activate()
           vehicleRepository.save(vehicle)
       }
   }
   ```

저희는 **둘을 조합**했다:
- 단일 엔티티 로직: 도메인 엔티티
- 여러 엔티티/외부 연동: UseCase

### Q: 멀티 모듈 구조는?

**답변:**
```
project/
├── app-api/              # API 서버 (Inbound Adapter)
├── app-consumer/         # Kafka 컨슈머 (Inbound Adapter)
├── adapter-persistence/  # DB 어댑터 (Outbound Adapter)
├── adapter-kafka/        # Kafka 어댑터 (Outbound Adapter)
├── application/          # UseCase, Port
└── domain/               # 순수 도메인 로직
```

의존성:
```
app-api ─────────────────────────┐
app-consumer ────────────────────┼──▶ application ──▶ domain
adapter-persistence ─────────────┤
adapter-kafka ───────────────────┘
```

- `domain`: 어떤 모듈에도 의존하지 않음
- `application`: domain만 의존
- `adapter-*`: application, domain 의존
- `app-*`: 필요한 adapter 조합

---

## 관련 개념 정리

| 개념 | 설명 |
|------|------|
| Port | 외부와 통신하는 인터페이스 |
| Adapter | Port의 실제 구현 |
| Inbound/Driving | 외부 → 내부 (Controller, Consumer) |
| Outbound/Driven | 내부 → 외부 (Repository, Client) |
| UseCase | 비즈니스 로직 오케스트레이션 |
| Domain | 순수 비즈니스 로직, 인프라 무관 |
| Clean Architecture | Uncle Bob의 유사 아키텍처 |
| Onion Architecture | 유사 아키텍처 |

---

## 다이어그램

```
┌─────────────────────────────────────────────────────────────┐
│                        Adapters (In)                        │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │ Controller  │  │  Consumer   │  │  Scheduler  │         │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘         │
├─────────┼────────────────┼────────────────┼─────────────────┤
│         └────────────────┼────────────────┘                 │
│                          ▼                                  │
│  ┌───────────────────────────────────────────────────────┐  │
│  │                    Port (In)                          │  │
│  │                    UseCase                            │  │
│  └───────────────────────────────────────────────────────┘  │
│                          │                                  │
│  ┌───────────────────────▼───────────────────────────────┐  │
│  │                                                       │  │
│  │                    Domain Core                        │  │
│  │               (Entity, Value Object)                  │  │
│  │                                                       │  │
│  └───────────────────────────────────────────────────────┘  │
│                          │                                  │
│  ┌───────────────────────▼───────────────────────────────┐  │
│  │                    Port (Out)                         │  │
│  │              Repository, Client                       │  │
│  └───────────────────────────────────────────────────────┘  │
│         ┌────────────────┼────────────────┐                 │
│         ▼                ▼                ▼                 │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │    JPA      │  │    Kafka    │  │  HTTP API   │         │
│  │  Adapter    │  │  Adapter    │  │  Adapter    │         │
│  └─────────────┘  └─────────────┘  └─────────────┘         │
│                        Adapters (Out)                       │
└─────────────────────────────────────────────────────────────┘
```

---

## 기술 선택과 Trade-off

### 왜 Hexagonal Architecture를 선택했는가?

**대안 비교:**

| 아키텍처 | 복잡도 | 테스트 용이성 | 유연성 | 학습 곡선 |
|----------|--------|--------------|--------|----------|
| **Layered** | 낮음 | 낮음 | 낮음 | 낮음 |
| **Hexagonal** | 중간 | 높음 | 높음 | 중간 |
| **Clean** | 높음 | 높음 | 높음 | 높음 |
| **Vertical Slice** | 중간 | 중간 | 중간 | 중간 |

**Hexagonal 선택 이유:**
- 마이크로서비스에서 어댑터 교체 빈번 (DB, Kafka, 외부 API)
- 테스트 시 Mock 어댑터로 교체 용이
- Clean Architecture보다 실용적 (계층 4개 → 3개)

### @ComponentScan vs @Import Trade-off

| 방식 | 편의성 | 명시성 | 제어력 | 문제 발생 시 디버깅 |
|------|--------|--------|--------|-------------------|
| **@ComponentScan** | 높음 | 낮음 | 낮음 | 어려움 |
| **@Import** | 낮음 | 높음 | 높음 | 쉬움 |
| **혼합** | 중간 | 중간 | 중간 | 중간 |

**@Import 선택 이유:**
- 어떤 빈이 활성화되는지 코드에서 명확히 파악
- 멀티 모듈에서 의도치 않은 빈 등록 방지
- "암묵적 vs 명시적" → 비즈니스 코드는 명시적으로

**경계 설정:**
```
인프라 (AutoConfiguration) → 암묵적 (Spring Boot가 처리)
비즈니스 (@Import) → 명시적 (개발자가 관리)
```

### Port 인터페이스 세분화 Trade-off

| 방식 | 인터페이스 수 | 단일 책임 | 복잡도 |
|------|--------------|----------|--------|
| **Repository 하나** | 1개 | 낮음 | 낮음 |
| **UseCase별 분리** | 여러 개 | 높음 | 높음 |
| **역할별 분리** | 중간 | 중간 | 중간 |

**역할별 분리 선택:**
```kotlin
// 읽기/쓰기 분리
interface VehicleReader { fun findById(id: String): Vehicle? }
interface VehicleWriter { fun save(vehicle: Vehicle): Vehicle }

// UseCase는 필요한 Port만 의존
class GetVehicleUseCase(private val reader: VehicleReader)
class RegisterVehicleUseCase(private val writer: VehicleWriter)
```

**이유:**
- UseCase별 분리: 인터페이스 폭발
- 단일 Repository: 불필요한 의존성 포함
- **역할별 분리가 균형점**

### 도메인 모델 Rich vs Anemic

| 모델 | 비즈니스 로직 위치 | 테스트 용이성 | 재사용성 |
|------|-------------------|--------------|----------|
| **Anemic** | UseCase/Service | 높음 | 낮음 |
| **Rich** | Domain Entity | 중간 | 높음 |
| **혼합** | 상황에 따라 | 높음 | 높음 |

**혼합 선택:**
- 단일 엔티티 로직: 도메인 엔티티 내부
- 여러 엔티티/외부 연동: UseCase

```kotlin
// Rich: 단일 엔티티 검증/상태 변경
class Vehicle {
    fun activate() {
        require(status == INACTIVE)
        status = ACTIVE
    }
}

// UseCase: 외부 연동, 트랜잭션
class RegisterVehicleUseCase {
    fun execute(...) {
        vehicle.activate()
        vehicleRepository.save(vehicle)
        eventPublisher.publish(VehicleActivated(vehicle.id))
    }
}
```

### 모듈 경계 설정 Trade-off

| 구조 | 재사용성 | 빌드 시간 | 의존성 관리 |
|------|----------|----------|-------------|
| **모놀리식** | 높음 | 느림 | 어려움 |
| **계층별** | 중간 | 중간 | 중간 |
| **기능별** | 낮음 | 빠름 | 쉬움 |

**계층별 + 어댑터별 선택:**
```
app-api, app-consumer          ← 진입점별
adapter-persistence, adapter-kafka  ← 인프라별
application, domain            ← 계층별
```

**이유:**
- 같은 도메인을 여러 앱에서 공유
- 어댑터 독립 배포/테스트 가능
- 빌드 시간: 변경된 모듈만 재빌드

---

## 블로그 링크

- [Selectively Opinionated Spring Boot (1) - @ComponentScan의 함정](https://gyeom.github.io/dev-notes/posts/2024-03-15-spring-component-scan-philosophy-part1/)
- [Selectively Opinionated Spring Boot (2) - 멀티앱, 하나의 코드베이스](https://gyeom.github.io/dev-notes/posts/2024-03-18-spring-component-scan-philosophy-part2/)
- [Selectively Opinionated Spring Boot (3) - Mock 남용 없는 통합 테스트](https://gyeom.github.io/dev-notes/posts/2024-03-22-spring-component-scan-philosophy-part3/)

---

*다음: [13-multi-module.md](./13-multi-module.md)*
