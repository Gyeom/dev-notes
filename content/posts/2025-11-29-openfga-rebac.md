---
title: "OpenFGA와 ReBAC: 관계 기반 접근 제어 시스템"
date: 2025-11-29
draft: false
tags: ["OpenFGA", "ReBAC", "권한", "인증", "Spring Boot"]
categories: ["Backend"]
summary: "Google Zanzibar 기반 오픈소스 OpenFGA를 활용한 관계 기반 접근 제어 구현"
---

## ReBAC이란?

ReBAC(Relationship-Based Access Control)은 사용자와 리소스 간의 관계를 기반으로 권한을 결정하는 접근 제어 모델이다. 기존 RBAC(Role-Based Access Control)과 달리 동적이고 세밀한 권한 관리가 가능하다.

### RBAC vs ReBAC

**RBAC의 한계:**
- 역할이 고정적이다. 사용자는 admin, editor, viewer 같은 정적 역할을 부여받는다.
- 리소스 간 관계를 표현하기 어렵다. "문서 A의 소유자는 폴더 B에도 접근 가능"처럼 계층 구조를 다루기 복잡하다.
- 규모가 커질수록 역할이 폭발적으로 증가한다.

**ReBAC의 장점:**
- 관계 기반으로 권한을 판단한다. "Alice는 Doc1의 owner다", "Doc1은 Folder1에 속한다"처럼 관계를 정의한다.
- 계층적 권한 상속이 자연스럽다. 폴더의 owner는 하위 문서에도 자동으로 권한을 가진다.
- 동적 권한 계산이 가능하다. 런타임에 관계 그래프를 탐색해 권한을 결정한다.

## OpenFGA

OpenFGA는 Google의 Zanzibar 논문을 기반으로 한 오픈소스 권한 관리 시스템이다. CNCF Sandbox 프로젝트로, Auth0에서 개발했다.

### 핵심 개념

**1. Authorization Model (스키마)**

DSL로 권한 모델을 정의한다.

```dsl
model
  schema 1.1

type user

type document
  relations
    define owner: [user]
    define editor: [user] or owner
    define viewer: [user] or editor
    define can_view: viewer
    define can_edit: editor
    define can_delete: owner

type folder
  relations
    define owner: [user]
    define parent: [folder]
    define viewer: [user] or owner or viewer from parent
```

- `owner`, `editor`, `viewer`: 사용자와 문서 간의 관계
- `can_view`, `can_edit`: 실제 권한 체크 시 사용하는 relation
- `viewer from parent`: 부모 폴더의 viewer는 하위 문서도 볼 수 있다

**2. Relationship Tuple**

실제 관계 데이터는 튜플로 저장된다.

```json
{
  "user": "user:alice",
  "relation": "owner",
  "object": "document:readme"
}
```

이 튜플은 "alice는 readme 문서의 owner다"를 의미한다.

**3. Check API**

권한 체크는 Check API로 수행한다.

```http
POST /stores/{store_id}/check
{
  "tuple_key": {
    "user": "user:alice",
    "relation": "can_edit",
    "object": "document:readme"
  }
}
```

응답:
```json
{
  "allowed": true
}
```

OpenFGA는 관계 그래프를 탐색해 alice가 readme를 편집할 수 있는지 계산한다.

### 아키텍처

```
┌─────────────────┐
│  Application    │
└────────┬────────┘
         │ gRPC/HTTP
┌────────▼────────┐
│    OpenFGA      │
│   (Server)      │
├─────────────────┤
│ Authorization   │
│ Model Engine    │
├─────────────────┤
│ Relationship    │
│ Storage         │
└────────┬────────┘
         │
┌────────▼────────┐
│  PostgreSQL     │
│  MySQL / Memory │
└─────────────────┘
```

- OpenFGA 서버가 권한 체크 로직을 담당한다
- 관계 튜플은 DB에 저장된다
- 애플리케이션은 gRPC 또는 REST API로 통신한다

## Spring Boot 연동

### 의존성 추가

```gradle
dependencies {
    implementation 'dev.openfga:openfga-sdk:0.3.0'
}
```

### OpenFGA 클라이언트 설정

```java
@Configuration
public class OpenFgaConfig {

    @Bean
    public OpenFgaClient openFgaClient() {
        ClientConfiguration config = new ClientConfiguration()
            .apiUrl("http://localhost:8080")
            .storeId("01HXXX...")
            .authorizationModelId("01HYYY...");

        return new OpenFgaClient(config);
    }
}
```

### 권한 체크 서비스

```java
@Service
@RequiredArgsConstructor
public class AuthorizationService {

    private final OpenFgaClient fgaClient;

    public boolean canEdit(String userId, String documentId)
            throws FgaInvalidParameterException, FgaApiException {

        CheckRequest request = new CheckRequest()
            .user("user:" + userId)
            .relation("can_edit")
            ._object("document:" + documentId);

        CheckResponse response = fgaClient.check(request).get();
        return response.getAllowed();
    }

    public void grantOwnership(String userId, String documentId)
            throws FgaInvalidParameterException, FgaApiException {

        TupleKey tuple = new TupleKey()
            .user("user:" + userId)
            .relation("owner")
            ._object("document:" + documentId);

        WriteRequest writeRequest = new WriteRequest()
            .writes(new TupleKeys().tupleKeys(List.of(tuple)));

        fgaClient.write(writeRequest).get();
    }
}
```

### 컨트롤러에서 사용

```java
@RestController
@RequiredArgsConstructor
public class DocumentController {

    private final AuthorizationService authService;

    @PutMapping("/documents/{id}")
    public ResponseEntity<Void> updateDocument(
            @PathVariable String id,
            @AuthenticationPrincipal String userId,
            @RequestBody DocumentUpdateDto dto) {

        if (!authService.canEdit(userId, id)) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN).build();
        }

        // 문서 업데이트 로직
        return ResponseEntity.ok().build();
    }
}
```

### Spring Security 통합

```java
@Component
@RequiredArgsConstructor
public class FgaPermissionEvaluator implements PermissionEvaluator {

    private final AuthorizationService authService;

    @Override
    public boolean hasPermission(Authentication auth, Object targetDomainObject, Object permission) {
        if (auth == null || targetDomainObject == null || !(permission instanceof String)) {
            return false;
        }

        String userId = auth.getName();
        String resource = targetDomainObject.toString();
        String relation = permission.toString();

        try {
            return authService.check(userId, relation, resource);
        } catch (Exception e) {
            return false;
        }
    }

    @Override
    public boolean hasPermission(Authentication auth, Serializable targetId,
                                 String targetType, Object permission) {
        return hasPermission(auth, targetType + ":" + targetId, permission);
    }
}
```

컨트롤러에서 선언적으로 사용:

```java
@PreAuthorize("hasPermission(#id, 'document', 'can_edit')")
@PutMapping("/documents/{id}")
public ResponseEntity<Void> updateDocument(@PathVariable String id, @RequestBody DocumentUpdateDto dto) {
    // 권한 체크는 이미 완료됨
    return ResponseEntity.ok().build();
}
```

## 실제 사용 사례

### Google Drive

Google Drive의 권한 모델은 ReBAC의 대표 사례다.

```dsl
type user
type group
  relations
    define member: [user]

type folder
  relations
    define owner: [user, group#member]
    define editor: [user, group#member] or owner
    define viewer: [user, group#member] or editor
    define parent: [folder]

type file
  relations
    define owner: [user, group#member]
    define editor: [user, group#member] or owner
    define viewer: [user, group#member] or editor
    define parent: [folder]
    define can_view: viewer or viewer from parent
    define can_edit: editor or editor from parent
```

- 파일/폴더의 owner, editor, viewer 관계
- 그룹 멤버십을 통한 권한 부여
- 부모 폴더의 권한 상속 (`viewer from parent`)

### GitHub Repository

```dsl
type user
type organization
  relations
    define member: [user]
    define owner: [user] or member

type repository
  relations
    define owner: [user, organization#owner]
    define admin: [user] or owner
    define writer: [user] or admin
    define reader: [user] or writer
    define can_push: writer
    define can_read: reader
```

- 조직의 owner는 저장소에도 권한을 가진다
- admin > writer > reader 계층 구조
- `can_push`, `can_read`로 실제 동작을 정의

### Multi-tenant SaaS

```dsl
type user
type tenant
  relations
    define admin: [user]
    define member: [user] or admin

type project
  relations
    define tenant: [tenant]
    define owner: [user]
    define member: [user] or owner or member from tenant
    define can_view: member
    define can_edit: owner
```

- 테넌트의 모든 member는 프로젝트를 볼 수 있다
- 프로젝트 owner만 편집할 수 있다
- 테넌트 admin은 자동으로 모든 프로젝트의 member다

## 성능 최적화

### 1. 캐싱

OpenFGA는 체크 결과를 캐싱한다. 자주 체크하는 권한은 Redis에 캐시하면 성능이 개선된다.

```java
@Cacheable(value = "permissions", key = "#userId + ':' + #relation + ':' + #object")
public boolean check(String userId, String relation, String object) {
    return authService.check(userId, relation, object);
}
```

### 2. Batch Check

여러 권한을 한 번에 체크한다.

```java
List<TupleKey> tuples = documents.stream()
    .map(doc -> new TupleKey()
        .user("user:" + userId)
        .relation("can_view")
        ._object("document:" + doc.getId()))
    .toList();

BatchCheckRequest request = new BatchCheckRequest()
    .checks(tuples);

BatchCheckResponse response = fgaClient.batchCheck(request).get();
```

### 3. List Objects API

"사용자가 볼 수 있는 모든 문서"처럼 역방향 쿼리는 List Objects API를 사용한다.

```http
POST /stores/{store_id}/list-objects
{
  "user": "user:alice",
  "relation": "can_view",
  "type": "document"
}
```

## 마무리

OpenFGA는 복잡한 권한 관리를 선언적으로 해결한다. Google Drive처럼 계층적 권한 구조가 필요하거나, GitHub처럼 조직-팀-레포 관계가 얽혀있는 경우 ReBAC이 적합하다.

Spring Boot와 통합도 간단하고, CNCF 프로젝트라 장기 지원도 기대할 수 있다. 다만 러닝 커브가 있고, 관계 그래프가 복잡해지면 성능 튜닝이 필요하다는 점은 고려해야 한다.

## 참고

- [OpenFGA 공식 문서](https://openfga.dev/docs)
- [Google Zanzibar 논문](https://research.google/pubs/pub48190/)
- [OpenFGA Playground](https://play.fga.dev/)
