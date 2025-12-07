# 멀티모듈 설계

## 이력서 연결

> "Hexagonal Architecture 기반 멀티모듈 설계"
> "어댑터별 모듈 분리"
> "@Import 기반 명시적 빈 구성"

---

## 핵심 답변 (STAR)

### Situation (상황)
- 42dot Vehicle Platform, 여러 앱(API, Consumer)이 같은 도메인 로직 공유
- 모놀리식 프로젝트에서 빌드 시간 증가
- 의존성 관리 복잡

### Task (과제)
- 코드 재사용성 향상
- 빌드 시간 단축
- 의존성 명확화

### Action (행동)
1. **Hexagonal 기반 모듈 분리**
   - domain: 순수 비즈니스 로직
   - application: UseCase, Port
   - adapter: 인프라 구현
   - app: 실행 가능한 앱

2. **의존성 방향 정립**
   - 모든 의존성이 domain을 향함
   - adapter가 application에 의존

3. **빌드 최적화**
   - 변경된 모듈만 재빌드
   - Gradle Configuration Cache

### Result (결과)
- 빌드 시간 50% 단축
- 코드 재사용성 향상
- 새 앱 추가 시 기존 모듈 조합만으로 구성

---

## 예상 질문

### Q1: 멀티모듈 구조를 설명해주세요

**답변:**

```
project/
├── app-api/              # API 서버 (Inbound Adapter)
├── app-consumer/         # Kafka 컨슈머 (Inbound Adapter)
├── adapter-persistence/  # DB 어댑터 (Outbound Adapter)
├── adapter-kafka/        # Kafka 어댑터 (Outbound Adapter)
├── adapter-client/       # HTTP 클라이언트 (Outbound Adapter)
├── application/          # UseCase, Port
└── domain/               # 순수 도메인 로직
```

**의존성 방향:**
```
app-api ─────────────────────────┐
app-consumer ────────────────────┼──▶ application ──▶ domain
adapter-persistence ─────────────┤
adapter-kafka ───────────────────┘
```

- `domain`: 어떤 모듈에도 의존하지 않음 (순수)
- `application`: domain만 의존
- `adapter-*`: application, domain 의존
- `app-*`: 필요한 adapter 조합

### Q2: 모듈 분리 기준은?

**답변:**

| 기준 | 분리 | 예시 |
|------|------|------|
| **계층** | 도메인 / 어플리케이션 / 어댑터 | domain, application |
| **인프라** | DB, Kafka, HTTP 등 | adapter-persistence |
| **실행 단위** | API, Consumer, Batch | app-api, app-consumer |
| **배포 단위** | 독립 배포 필요 여부 | 마이크로서비스 |

**우리 프로젝트:**
- **계층 분리**: Hexagonal Architecture 적용
- **인프라 분리**: 특정 인프라 변경 시 해당 모듈만 수정
- **실행 단위 분리**: 같은 도메인, 다른 진입점

### Q3: 모듈 간 의존성 관리는?

**답변:**

**build.gradle.kts:**
```kotlin
// domain 모듈 (의존성 없음)
dependencies {
    // 외부 의존성 최소화
}

// application 모듈
dependencies {
    implementation(project(":domain"))
}

// adapter-persistence 모듈
dependencies {
    implementation(project(":application"))
    implementation(project(":domain"))
    implementation("org.springframework.boot:spring-boot-starter-data-jpa")
}

// app-api 모듈
dependencies {
    implementation(project(":application"))
    implementation(project(":domain"))
    implementation(project(":adapter-persistence"))
    implementation(project(":adapter-kafka"))
    implementation("org.springframework.boot:spring-boot-starter-web")
}
```

**규칙:**
- domain은 Spring 의존성 없음
- adapter가 application을 의존, 반대 불가
- 순환 의존성 금지

### Q4: 같은 도메인, 다른 앱은 어떻게 구성하나요?

**답변:**
`profiles.include`로 Config를 조합한다.

```yaml
# app-api/application.yml
spring:
  profiles:
    include:
      - persistence
      - kafka-producer
      - cache

# app-consumer/application.yml
spring:
  profiles:
    include:
      - persistence
      - kafka-consumer
```

**각 모듈의 Config:**
```kotlin
// adapter-persistence 모듈
@Configuration
@Profile("persistence")
@Import(JpaConfig::class, RepositoryConfig::class)
class PersistenceAdapterConfig

// adapter-kafka 모듈
@Configuration
@Profile("kafka-consumer")
@Import(KafkaConsumerConfig::class)
class KafkaConsumerAdapterConfig

@Configuration
@Profile("kafka-producer")
@Import(KafkaProducerConfig::class)
class KafkaProducerAdapterConfig
```

**장점:**
- 필요한 어댑터만 Import
- 새 앱 추가 시 조합만으로 구성
- 불필요한 빈 로딩 방지

### Q5: 빌드 최적화는 어떻게?

**답변:**

**1. 변경된 모듈만 재빌드**
```bash
# domain만 변경되면 domain만 재빌드
# 하위 모듈은 캐시 사용
./gradlew build
```

**2. Gradle Configuration Cache**
```kotlin
// gradle.properties
org.gradle.configuration-cache=true
```

**3. Parallel Build**
```kotlin
// gradle.properties
org.gradle.parallel=true
```

**4. Build Cache**
```kotlin
// settings.gradle.kts
buildCache {
    local { isEnabled = true }
}
```

**결과:**
- 전체 빌드: 10분 → 5분
- 증분 빌드: 30초 이내

---

## 꼬리 질문 대비

### Q: api 의존성 vs implementation 차이는?

**답변:**

| 구분 | api | implementation |
|------|-----|----------------|
| 전이 의존성 | 노출됨 | 숨겨짐 |
| 재컴파일 범위 | 하위 모듈 포함 | 해당 모듈만 |
| 사용 시점 | 인터페이스 노출 | 내부 구현 |

```kotlin
// adapter-persistence/build.gradle.kts
dependencies {
    api(project(":domain"))  // domain 타입을 외부에 노출
    implementation("org.springframework.boot:spring-boot-starter-data-jpa")  // 내부만 사용
}
```

**규칙:**
- 기본은 `implementation`
- 반환 타입이나 파라미터에 사용되면 `api`

### Q: 순환 의존성 방지는?

**답변:**

```kotlin
// ❌ 순환 의존성
module-a → module-b → module-a

// ✅ 해결: 인터페이스 분리
module-a → interface (in module-common)
module-b → interface
```

Gradle은 순환 의존성을 허용하지 않으므로 빌드 시 바로 발견된다.

**예방:**
- Port 인터페이스를 application 모듈에 정의
- 구현체는 adapter 모듈에
- 의존성 방향 항상 안쪽으로

### Q: 공통 유틸리티는 어디에?

**답변:**

```
project/
├── common/              # 순수 유틸리티
├── common-spring/       # Spring 관련 유틸리티
└── ...
```

| 모듈 | 내용 | 의존성 |
|------|------|--------|
| common | 순수 Kotlin 유틸 | 없음 |
| common-spring | Spring 관련 유틸 | Spring |

**주의:**
- common이 비대해지면 분리 고려
- 너무 많은 것을 common에 넣지 말 것

---

## 관련 개념 정리

| 개념 | 설명 |
|------|------|
| 모듈 | Gradle의 독립적 빌드 단위 |
| api vs implementation | 의존성 전이 여부 |
| Build Cache | 빌드 결과 캐싱 |
| Configuration Cache | Gradle 설정 캐싱 |
| 순환 의존성 | 모듈 간 상호 의존 (금지) |

---

## 아키텍처 다이어그램

```
┌───────────────────────────────────────────────────────────────┐
│                        App Layer                              │
│   ┌──────────────┐           ┌──────────────┐                │
│   │   app-api    │           │ app-consumer │                │
│   │  (REST API)  │           │   (Kafka)    │                │
│   └──────┬───────┘           └──────┬───────┘                │
└──────────┼──────────────────────────┼────────────────────────┘
           │                          │
           └────────────┬─────────────┘
                        │
┌───────────────────────▼───────────────────────────────────────┐
│                     Adapter Layer                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐           │
│  │ persistence │  │    kafka    │  │   client    │           │
│  │  (JPA/DB)   │  │ (Producer)  │  │ (HTTP API)  │           │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘           │
└─────────┼────────────────┼────────────────┼──────────────────┘
          │                │                │
          └────────────────┼────────────────┘
                           │
┌──────────────────────────▼────────────────────────────────────┐
│                   Application Layer                           │
│                 ┌─────────────────────┐                       │
│                 │     UseCase         │                       │
│                 │     Port            │                       │
│                 └──────────┬──────────┘                       │
└────────────────────────────┼──────────────────────────────────┘
                             │
┌────────────────────────────▼──────────────────────────────────┐
│                      Domain Layer                             │
│                 ┌─────────────────────┐                       │
│                 │   Entity            │                       │
│                 │   Value Object      │                       │
│                 │   Domain Service    │                       │
│                 └─────────────────────┘                       │
└───────────────────────────────────────────────────────────────┘
```

---

## 블로그 링크

- [Selectively Opinionated Spring Boot (2) - 멀티앱, 하나의 코드베이스](https://gyeom.github.io/dev-notes/posts/2024-03-18-spring-component-scan-philosophy-part2/)

---

*다음: [14-kotlin-jpa.md](./14-kotlin-jpa.md)*
