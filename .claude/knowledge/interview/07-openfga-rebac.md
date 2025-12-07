# OpenFGA와 ReBAC 권한 설계

## 이력서 연결

> "OpenFGA 기반 ReBAC(Relationship-Based Access Control) 권한 관리 시스템 설계"
> "복잡한 계층 구조의 권한 관계를 선언적으로 정의"

---

## 핵심 답변 (STAR)

### Situation (상황)
- 42dot Vehicle Platform, 차량-사용자 간 복잡한 권한 구조
- 기존 RBAC로는 "소유자가 하위 리소스에 자동 접근" 같은 관계 표현 어려움
- 코드에 복잡한 권한 로직이 산재

### Task (과제)
- 계층적 권한 관계 선언적 정의
- 코드에서 권한 로직 분리
- 성능과 확장성 확보

### Action (행동)
1. **ReBAC 모델 설계**
   - 객체 간 관계(owner, editor, viewer, parent)로 권한 정의
   - `from parent` 구문으로 계층 구조 자동 처리

2. **OpenFGA 도입**
   - Google Zanzibar 기반 오픈소스
   - 스키마 DSL로 권한 모델 정의
   - Check API로 권한 확인

3. **Spring Boot 연동**
   - OpenFGA SDK 통합
   - 권한 체크 서비스 구현
   - 관계 튜플 생성/삭제 API

4. **성능 최적화**
   - 테넌트 ID로 먼저 필터링 (Pragmatic Filtering)
   - BatchCheck로 N+1 문제 해결

### Result (결과)
- 복잡한 권한 로직 선언적 정의
- 코드 복잡도 감소
- 새로운 권한 요구사항 빠르게 반영

---

## 예상 질문

### Q1: RBAC와 ReBAC의 차이가 뭔가요?

**답변:**

**RBAC (Role-Based Access Control)**:
```
사용자 → 역할(Admin, Editor, Viewer) → 권한(Read, Write, Delete)
```
- 사용자에게 역할 부여, 역할에 권한 매핑
- 단순하지만 계층적 관계 표현 어려움

**ReBAC (Relationship-Based Access Control)**:
```
alice는 folder:docs의 owner다
folder:docs는 file:report.pdf의 parent다
→ alice는 file:report.pdf를 read할 수 있다
```
- 객체 간 **관계**를 기반으로 권한 결정
- 관계를 선언하면 권한이 자동으로 추론

| 기준 | RBAC | ReBAC |
|------|------|-------|
| 권한 결정 | 역할 기반 | 관계 기반 |
| 계층 구조 | 코드로 구현 필요 | 선언적 정의 |
| 복잡도 | 단순 | 복잡하지만 유연 |
| 적합한 경우 | 정적 권한 | 동적, 계층적 권한 |

### Q2: OpenFGA가 뭔가요?

**답변:**
Auth0에서 만든 오픈소스 권한 관리 시스템이다. Google의 Zanzibar 논문을 기반으로 한다.

**주요 구성요소:**
1. **Authorization Model**: DSL로 권한 규칙 정의
2. **Relationship Tuples**: 실제 관계 데이터 저장 (`user:alice, owner, folder:docs`)
3. **Check API**: 권한 확인 요청 처리

```fga
type user

type folder
  relations
    define owner: [user]
    define viewer: [user] or owner
    define parent: [folder]
    define can_read: viewer or can_read from parent
```

`from parent` 구문이 계층 구조를 자동으로 처리한다.

### Q3: 권한 체크는 어떻게 동작하나요?

**답변:**
그래프 탐색 방식으로 동작한다.

```
alice가 file:report.pdf의 can_read 권한이 있는가?

1. alice가 file:report.pdf의 viewer인가? → 아니오
2. file:report.pdf의 parent는? → folder:docs
3. alice가 folder:docs의 can_read 권한이 있는가? → 예 (owner이므로)
4. 결과: 허용
```

OpenFGA가 관계 그래프를 탐색하여 권한을 추론한다.

### Q4: 성능 이슈는 없었나요?

**답변:**
몇 가지 성능 고려사항이 있다.

**문제 1: Tuple 증가에 따른 성능 저하**
- 62 tuples → 5ms
- 310K tuples → 300ms ~ 3초

**문제 2: 검색 + 권한 통합**
- Search then Check: 검색 결과에 각각 권한 체크 (N+1)
- List Objects then Search: 접근 가능 ID 먼저 조회 (최대 1,000개 제한)

**해결책: Pragmatic Filtering**
- 테넌트 ID로 먼저 필터링 → 범위 축소
- BatchCheck API 사용 → 여러 권한 한 번에 체크
- 필요시 Local Index 구축

```kotlin
// 테넌트로 먼저 필터링
val candidates = documentRepository.findByTenantId(tenantId)

// BatchCheck로 한 번에 권한 체크
val checkResults = fgaClient.batchCheck(candidates.map { ... })
```

### Q5: RBAC가 적합한 경우는 언제인가요?

**답변:**

**ReBAC가 적합한 경우:**
- 계층 구조 리소스 (폴더/파일)
- 조직/팀 단위 권한 관리
- 동적으로 변하는 권한 관계
- Google Drive, GitHub 같은 구조

**RBAC가 적합한 경우:**
- 단순한 역할 기반 권한
- 정적인 권한 구조
- 작은 규모의 서비스
- Admin/User 정도의 구분

---

## 꼬리 질문 대비

### Q: 관계 튜플은 어떻게 저장하나요?

**답변:**
`user:alice, owner, folder:docs` 형태로 저장한다.

```kotlin
// 소유 관계 생성
val tuple = ClientTupleKey()
    .user("user:${userId}")
    .relation("owner")
    ._object("folder:${folderId}")

fgaClient.write(ClientWriteRequest().writes(listOf(tuple))).get()
```

OpenFGA가 내부적으로 PostgreSQL/MySQL에 저장한다.

### Q: Zanzibar가 뭔가요?

**답변:**
Google이 2019년에 발표한 논문으로, Google의 글로벌 인가 시스템이다.

특징:
- **Tuple 기반**: `(user, relation, object)` 형태
- **그래프 탐색**: 관계 그래프를 탐색해 권한 결정
- **Eventual Consistency**: 성능을 위해 최종 일관성 선택
- **대규모 서비스 검증**: Google Drive, Calendar, Cloud 등에서 사용

OpenFGA는 Zanzibar의 오픈소스 구현체 중 하나다.

### Q: 일관성(Consistency) 문제는 어떻게 처리하나요?

**답변:**
OpenFGA는 기본적으로 Eventual Consistency다.

문제 상황:
1. 권한 부여 (Write)
2. 즉시 권한 체크 (Check) → 아직 반영 안 됨

해결책:
- `consistency_preference: MINIMIZE_LATENCY` (기본값, 빠르지만 최신 아닐 수 있음)
- `consistency_preference: HIGHER_CONSISTENCY` (느리지만 최신 보장)
- 중요한 경우 Write 후 약간의 지연 추가

### Q: 모델 복잡도가 성능에 미치는 영향은?

**답변:**

```fga
// 비용이 높은 패턴
define viewer: editor and not blocked

// 상대적으로 저렴한 패턴
define viewer: editor or guest
```

- `and`, `but not` 연산은 `or`보다 비용이 높다
- 깊은 계층 구조는 그래프 탐색 비용 증가
- 모델 설계 시 성능 고려 필요

---

## 관련 개념 정리

| 개념 | 설명 |
|------|------|
| RBAC | Role-Based Access Control, 역할 기반 권한 |
| ReBAC | Relationship-Based Access Control, 관계 기반 권한 |
| Zanzibar | Google의 글로벌 인가 시스템 논문 |
| OpenFGA | Zanzibar 기반 오픈소스 인가 엔진 |
| Tuple | `(user, relation, object)` 형태의 관계 데이터 |
| Authorization Model | DSL로 정의된 권한 규칙 |
| Check API | 권한 확인 요청 처리 API |
| ListObjects | 특정 사용자가 접근 가능한 객체 목록 조회 |

---

## 스키마 예시 (Google Drive)

```fga
model
  schema 1.1

type user

type folder
  relations
    define owner: [user]
    define editor: [user] or owner
    define viewer: [user] or editor
    define parent: [folder]
    define can_read: viewer or can_read from parent
    define can_write: editor or can_write from parent
    define can_delete: owner or can_delete from parent

type file
  relations
    define owner: [user]
    define editor: [user] or owner
    define viewer: [user] or editor
    define parent: [folder]
    define can_read: viewer or can_read from parent
    define can_write: editor or can_write from parent
```

---

## 아키텍처 다이어그램

```
┌─────────────────┐
│  애플리케이션    │
│  (Spring Boot)  │
└────────┬────────┘
         │
         ▼
┌─────────────────────────────────────────┐
│              OpenFGA                     │
│  ┌────────────────┐  ┌────────────────┐ │
│  │ Authorization  │  │  Relationship  │ │
│  │     Model      │  │    Tuples      │ │
│  │     (DSL)      │  │   (Storage)    │ │
│  └────────────────┘  └────────────────┘ │
└─────────────────────────────────────────┘
         │
         ▼
    ┌──────────┐
    │ PostgreSQL│
    └──────────┘
```

---

## 기술 선택과 Trade-off

### 왜 ReBAC을 선택했는가?

**대안 비교:**

| 방식 | 계층 구조 | 유연성 | 구현 복잡도 | 성능 |
|------|----------|--------|-------------|------|
| **RBAC (역할 기반)** | 코드로 구현 | 낮음 | 쉬움 | 빠름 |
| **ABAC (속성 기반)** | 조건으로 표현 | 높음 | 중간 | 중간 |
| **ReBAC (관계 기반)** | 선언적 정의 | 매우 높음 | 높음 | 중간 |

**ReBAC 선택 이유:**
- 차량 → 사용자 → 조직 계층 구조가 복잡
- RBAC로 구현 시 `if-else` 지옥
- **관계를 선언하면 권한이 자동 추론**되는 ReBAC가 적합

### OpenFGA vs 대안

| 도구 | 언어 | 라이선스 | 커뮤니티 | 성능 |
|------|------|----------|----------|------|
| **OpenFGA** | Go | Apache 2.0 | 활발 | 좋음 |
| **SpiceDB** | Go | Apache 2.0 | 활발 | 매우 좋음 |
| **Casbin** | Go | Apache 2.0 | 매우 활발 | 좋음 |
| **OPA** | Go | Apache 2.0 | 매우 활발 | 좋음 |

**OpenFGA 선택 이유:**
- Auth0이 개발, 안정적인 유지보수
- 스키마 DSL이 직관적
- SDK 지원 (Java, Go, Python 등)
- 자체 호스팅 쉬움 (Docker 이미지)

### Pragmatic Filtering Trade-off

| 방식 | 쿼리 | 권한 체크 | 성능 | 정확도 |
|------|------|----------|------|--------|
| **Search then Check** | DB 먼저 | 결과에 체크 | N+1 문제 | 정확 |
| **ListObjects then Search** | FGA 먼저 | 결과로 DB 쿼리 | 1,000개 제한 | 정확 |
| **Pragmatic Filtering** | 테넌트로 필터 | BatchCheck | 빠름 | 정확 |

**Pragmatic Filtering 선택 이유:**
- Search then Check: N+1 문제로 성능 저하
- ListObjects: 최대 1,000개 제한, 대규모 데이터에 부적합
- **테넌트 필터 + BatchCheck가 현실적 균형점**

### 일관성(Consistency) 선택

| 옵션 | 지연 | 정확도 | 사용 시점 |
|------|------|--------|----------|
| **MINIMIZE_LATENCY** | 낮음 | 약간 오래됨 | 일반 조회 |
| **HIGHER_CONSISTENCY** | 높음 | 최신 | 권한 변경 직후 |

**MINIMIZE_LATENCY 기본 선택 이유:**
- 대부분의 경우 약간의 지연 허용
- 권한 변경 직후만 HIGHER_CONSISTENCY
- 성능과 일관성의 Trade-off

### 모델 복잡도 Trade-off

**비용이 높은 패턴:**
```fga
// and, but not 연산은 비용 높음
define viewer: editor and not blocked
```

**비용이 낮은 패턴:**
```fga
// or 연산은 상대적으로 저렴
define viewer: editor or guest
```

**설계 원칙:**
- 깊은 계층: 그래프 탐색 비용 증가
- `and`, `but not`: 여러 경로 탐색 필요
- 모델 단순화로 성능과 유지보수성 확보

---

## 블로그 링크

- [OpenFGA와 ReBAC로 구현하는 관계 기반 권한 제어](https://gyeom.github.io/dev-notes/posts/2024-09-10-openfga-rebac/)
- [OpenFGA ReBAC 구현의 한계점 심층 분석](https://gyeom.github.io/dev-notes/posts/2025-01-15-openfga-rebac-limitations/)
- [ReBAC 그룹 패턴 실전 적용](https://gyeom.github.io/dev-notes/posts/2025-02-10-rebac-group-pattern-real-world/)

---

*다음: [08-rate-limiting.md](./08-rate-limiting.md)*
