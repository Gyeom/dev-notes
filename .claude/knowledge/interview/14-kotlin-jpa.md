# Kotlin JPA 엔티티 설계

## 이력서 연결

> "Kotlin JPA 엔티티 설계 (Persistable 인터페이스 활용)"
> "Kotlin, Java, Spring Boot, JPA, QueryDSL"

---

## 핵심 답변 (STAR)

### Situation (상황)
- 42dot Vehicle Platform, Kotlin + Spring Boot + JPA
- UUID를 PK로 사용하는 엔티티 설계
- 새 엔티티 `save()` 시 불필요한 SELECT 발생

### Task (과제)
- Kotlin에서 JPA 엔티티 설계 Best Practice
- UUID PK 사용 시 merge 대신 persist 유도
- Null Safety와 JPA의 조화

### Action (행동)
1. **Persistable 인터페이스 구현**
   - `isNew()` 메서드로 새 엔티티 여부 판단
   - `@CreatedDate` 활용하여 판단 로직 단순화

2. **Data Class 대신 일반 Class 사용**
   - `equals()`, `hashCode()` 직접 구현
   - 프록시 호환성 유지

3. **Null Safety 전략**
   - `lateinit var` 또는 `by lazy` 활용
   - Non-null 필드에 대한 안전한 초기화

### Result (결과)
- 불필요한 SELECT 제거로 INSERT 성능 향상
- 일관된 엔티티 설계 패턴 정립
- 팀 내 Kotlin JPA 가이드 문서화

---

## 예상 질문

### Q1: Persistable 인터페이스는 왜 사용하나요?

**답변:**
JPA에서 `save()` 호출 시 새 엔티티인지 판단하는 방법 때문이다.

**문제 상황:**
```kotlin
// UUID PK 사용 시
@Entity
class Vehicle(
    @Id
    val id: UUID = UUID.randomUUID()  // 이미 ID가 있음!
)

// JPA 기본 동작
// 1. id가 있으면 기존 엔티티로 판단
// 2. SELECT로 존재 여부 확인
// 3. 없으면 INSERT, 있으면 UPDATE

repository.save(Vehicle())  // SELECT 후 INSERT (비효율)
```

**해결: Persistable 구현**
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

`isNew()`가 `true`를 반환하면 JPA는 SELECT 없이 바로 INSERT한다. `@CreatedDate`가 null이면 새 엔티티로 판단한다.

### Q2: Kotlin에서 JPA 엔티티 설계 시 주의점은?

**답변:**
네 가지 주의점이 있다.

**1. data class 사용 금지**
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

data class의 `equals()`는 모든 필드를 비교해서 컬렉션에서 문제가 발생한다.

**2. all-open 플러그인 필수**
```kotlin
// build.gradle.kts
plugins {
    kotlin("plugin.jpa")  // all-open for JPA annotations
}
```

JPA 프록시는 클래스를 상속하므로 `open` 키워드가 필요하다.

**3. no-arg 생성자**
```kotlin
// build.gradle.kts
plugins {
    kotlin("plugin.jpa")  // 자동으로 no-arg 생성자 추가
}
```

Hibernate는 리플렉션으로 인스턴스를 생성하므로 기본 생성자가 필요하다.

**4. nullable 처리**
```kotlin
@Entity
class Vehicle(
    @Id
    val id: UUID = UUID.randomUUID(),

    @Column(nullable = false)
    var name: String,  // non-null이지만 DB에서 로드 시 문제

) {
    // lateinit은 primitive 불가
    @Column(nullable = false)
    lateinit var description: String

    // 또는 기본값 제공
    @Column(nullable = false)
    var status: String = ""
}
```

### Q3: equals/hashCode는 어떻게 구현하나요?

**답변:**
**ID 기반 구현**을 권장한다.

```kotlin
@Entity
class Vehicle(
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    val id: Long? = null
) {
    // ID가 null일 수 있으므로 안전하게 처리
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other == null) return false
        // 프록시 대응: javaClass 대신 Hibernate.getClass 사용
        if (Hibernate.getClass(this) != Hibernate.getClass(other)) return false
        other as Vehicle
        return id != null && id == other.id
    }

    override fun hashCode(): Int = javaClass.hashCode()
}
```

**주의점:**
- `hashCode()`는 상수 반환 (ID가 persist 전/후 변경되므로)
- 프록시 클래스 대응 필요
- 비영속 엔티티끼리는 같지 않음

### Q4: 연관관계 매핑은 어떻게 하나요?

**답변:**

**양방향 연관관계:**
```kotlin
@Entity
class Order(
    @Id val id: UUID = UUID.randomUUID(),

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "user_id")
    var user: User? = null
) {
    @OneToMany(mappedBy = "order", cascade = [CascadeType.ALL])
    val items: MutableList<OrderItem> = mutableListOf()

    fun addItem(item: OrderItem) {
        items.add(item)
        item.order = this  // 양방향 동기화
    }
}
```

**Lazy Loading:**
```kotlin
// ❌ 프록시 문제
@ManyToOne  // 기본값 EAGER
val user: User

// ✅ 명시적 LAZY
@ManyToOne(fetch = FetchType.LAZY)
var user: User? = null  // nullable로 선언
```

Kotlin에서 non-null 타입으로 선언하면 프록시 초기화 전 NPE 발생할 수 있다.

### Q5: QueryDSL과 Kotlin 조합은?

**답변:**
kapt 또는 KSP로 Q클래스를 생성한다.

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

**Repository 예시:**
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

## 꼬리 질문 대비

### Q: @GeneratedValue와 UUID 차이는?

**답변:**

| 전략 | 장점 | 단점 |
|------|------|------|
| `IDENTITY` | DB가 ID 생성, 간단 | 배치 INSERT 불가, persist 후 ID 확정 |
| `SEQUENCE` | 배치 INSERT 가능 | DB 시퀀스 필요 |
| `UUID` | 분산 환경에 적합, persist 전 ID 확정 | 인덱스 성능 (랜덤 값) |

UUID 사용 시 정렬 가능한 형식 권장:
```kotlin
// 시간순 정렬 가능한 UUID v7
val id: UUID = Generators.timeBasedEpochGenerator().generate()
```

### Q: 영속성 컨텍스트와 Kotlin?

**답변:**
Kotlin의 val(불변)과 JPA의 dirty checking은 조화롭게 동작한다.

```kotlin
@Entity
class Vehicle(
    @Id val id: UUID = UUID.randomUUID(),
    var name: String  // 변경 가능
)

// 트랜잭션 내에서
val vehicle = repository.findById(id)
vehicle.name = "New Name"  // dirty checking 동작
// 트랜잭션 종료 시 자동 UPDATE
```

불변(val)으로 선언한 필드는 변경할 수 없어 의도치 않은 수정을 방지한다.

### Q: Spring Data JPA의 Kotlin 확장은?

**답변:**
Spring Data JPA는 Kotlin 확장 함수를 제공한다.

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

## 관련 개념 정리

| 개념 | 설명 |
|------|------|
| Persistable | `isNew()` 메서드로 새 엔티티 판단 인터페이스 |
| data class | Kotlin의 불변 데이터 클래스, JPA에서 사용 금지 |
| all-open | JPA 프록시를 위해 클래스를 open으로 만드는 플러그인 |
| no-arg | 기본 생성자를 자동 생성하는 플러그인 |
| Q클래스 | QueryDSL의 메타모델 클래스 |
| kapt | Kotlin Annotation Processing Tool |
| KSP | Kotlin Symbol Processing (kapt 대체) |

---

## 엔티티 템플릿

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

## 블로그 링크

- [Kotlin 기반 JPA 엔티티 설계 전략 (Medium)](https://medium.com/@rlaeorua369/kotlin-%EA%B8%B0%EB%B0%98-jpa-%EC%97%94%ED%8B%B0%ED%8B%B0-%EC%84%A4%EA%B3%84-%EC%A0%84%EB%9E%B5-28ccc31d0c2b)

---

*다음: [15-spring-core.md](./15-spring-core.md)*
