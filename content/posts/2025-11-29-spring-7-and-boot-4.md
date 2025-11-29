---
title: "Spring Framework 7.0과 Spring Boot 4.0 주요 변경사항"
date: 2025-11-29
draft: false
tags: ["Spring", "Spring Boot", "Java", "Jakarta EE", "Virtual Threads"]
categories: ["Backend"]
summary: "Java 17 필수, Jakarta EE 10+, Virtual Threads 지원 등 Spring 7.0과 Boot 4.0의 주요 변경사항과 마이그레이션 가이드"
---

Spring Framework 7.0과 Spring Boot 4.0이 출시되었다. 이번 메이저 버전은 현대적인 Java 생태계에 맞춘 대규모 업데이트를 담고 있다.

## 주요 변경사항

### Java 17+ 필수

Spring 7.0부터는 Java 17이 최소 요구사항이다. Java 8, 11 지원이 완전히 종료되었다.

```xml
<!-- Maven -->
<properties>
    <java.version>17</java.version>
</properties>
```

```gradle
// Gradle
java {
    sourceCompatibility = JavaVersion.VERSION_17
}
```

**Java 17의 주요 기능 활용**:
- Records를 DTO로 사용 가능
- Sealed Classes 지원
- Pattern Matching 개선
- Text Blocks

### Jakarta EE 10+ 지원

JavaX에서 Jakarta로의 완전한 전환이 이루어졌다.

**패키지 변경**:
```java
// Spring 6.x 이전
import javax.servlet.*;
import javax.persistence.*;

// Spring 7.0
import jakarta.servlet.*;
import jakarta.persistence.*;
```

**주요 의존성 업데이트**:
- Jakarta Servlet 6.0
- Jakarta Persistence (JPA) 3.1
- Jakarta Validation 3.0
- Jakarta Annotations 2.1

### Virtual Threads 지원 (Project Loom)

Java 21의 Virtual Threads가 기본으로 지원된다.

**활성화 방법**:
```yaml
# application.yml
spring:
  threads:
    virtual:
      enabled: true
```

또는 Java 시스템 프로퍼티:
```bash
-Dspring.threads.virtual.enabled=true
```

**톰캣과 함께 사용**:
```java
@Configuration
public class VirtualThreadConfig {

    @Bean
    public TomcatProtocolHandlerCustomizer<?> protocolHandlerVirtualThreadExecutorCustomizer() {
        return protocolHandler -> {
            protocolHandler.setExecutor(Executors.newVirtualThreadPerTaskExecutor());
        };
    }
}
```

**성능 개선**:
- 수천 개의 동시 요청 처리 가능
- 블로킹 I/O 작업 시 스레드 비용 최소화
- 기존 코드 수정 없이 성능 향상

### 새로운 HTTP Client

RestTemplate이 Deprecated되고 새로운 HTTP 인터페이스가 도입되었다.

**HTTP Interface 선언**:
```java
@HttpExchange("/api/users")
public interface UserClient {

    @GetExchange("/{id}")
    User getUser(@PathVariable Long id);

    @PostExchange
    User createUser(@RequestBody User user);

    @DeleteExchange("/{id}")
    void deleteUser(@PathVariable Long id);
}
```

**사용 방법**:
```java
@Configuration
public class HttpClientConfig {

    @Bean
    public UserClient userClient() {
        WebClient webClient = WebClient.builder()
            .baseUrl("http://localhost:8080")
            .build();

        HttpServiceProxyFactory factory = HttpServiceProxyFactory
            .builderFor(WebClientAdapter.create(webClient))
            .build();

        return factory.createClient(UserClient.class);
    }
}
```

**기존 코드 마이그레이션**:
```java
// RestTemplate (Deprecated)
RestTemplate restTemplate = new RestTemplate();
User user = restTemplate.getForObject("/api/users/1", User.class);

// 새로운 HTTP Interface
@Autowired
private UserClient userClient;

User user = userClient.getUser(1L);
```

### GraalVM 네이티브 이미지 개선

Spring Boot 3.x에서 도입된 네이티브 이미지 지원이 크게 개선되었다.

**빌드 설정**:
```gradle
plugins {
    id 'org.graalvm.buildtools.native' version '0.10.0'
}

graalvmNative {
    binaries {
        main {
            imageName = 'my-app'
            mainClass = 'com.example.Application'
            buildArgs.add('--verbose')
        }
    }
}
```

**네이티브 이미지 빌드**:
```bash
./gradlew nativeCompile
```

**성능 개선**:
- 시작 시간: 100ms 이하
- 메모리 사용: JVM 대비 1/5 수준
- 배포 용량: 50MB 이하

**제약사항**:
- 리플렉션 사용 제한
- 동적 프록시 사전 등록 필요
- 일부 라이브러리 호환성 이슈

### 기타 주요 변경사항

**Observability 개선**:
```yaml
management:
  tracing:
    sampling:
      probability: 1.0
  metrics:
    distribution:
      percentiles-histogram:
        http.server.requests: true
```

**Problem Details (RFC 7807) 기본 지원**:
```java
@RestControllerAdvice
public class GlobalExceptionHandler {

    @ExceptionHandler(NotFoundException.class)
    public ProblemDetail handleNotFound(NotFoundException ex) {
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(
            HttpStatus.NOT_FOUND,
            ex.getMessage()
        );
        problem.setTitle("Resource Not Found");
        return problem;
    }
}
```

## 마이그레이션 가이드

### 1. Java 버전 업그레이드

```bash
# SDKMAN 사용
sdk install java 21-tem
sdk use java 21-tem

# 프로젝트 빌드 도구 설정 업데이트
```

### 2. 의존성 업데이트

**Maven**:
```xml
<parent>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-parent</artifactId>
    <version>4.0.0</version>
</parent>
```

**Gradle**:
```gradle
plugins {
    id 'org.springframework.boot' version '4.0.0'
}
```

### 3. 패키지 변경 (javax → jakarta)

**자동 변환 도구 사용**:
```bash
# OpenRewrite 사용
./gradlew rewriteRun -Drewrite.activeRecipe=org.openrewrite.java.spring.boot4.UpgradeSpringBoot_4_0
```

**수동 변경**:
```bash
# IntelliJ IDEA에서 일괄 변경
# Edit > Find > Replace in Files
# javax. → jakarta.
```

### 4. Deprecated API 교체

**RestTemplate → HTTP Interface**:
```java
// 1. 인터페이스 정의
@HttpExchange("/api")
public interface ApiClient {
    @GetExchange("/data")
    Data getData();
}

// 2. Bean 등록
@Bean
public ApiClient apiClient(WebClient.Builder builder) {
    WebClient webClient = builder.baseUrl("http://api.example.com").build();
    HttpServiceProxyFactory factory = HttpServiceProxyFactory
        .builderFor(WebClientAdapter.create(webClient))
        .build();
    return factory.createClient(ApiClient.class);
}
```

### 5. 설정 변경 확인

**application.yml 마이그레이션**:
```bash
# Spring Boot CLI 사용
spring boot:properties-migrator
```

또는 의존성 추가:
```gradle
runtimeOnly 'org.springframework.boot:spring-boot-properties-migrator'
```

애플리케이션 실행 시 Deprecated된 설정에 대한 경고가 로그에 출력된다.

### 6. 테스트 실행

```bash
# 전체 테스트 실행
./gradlew test

# 통합 테스트
./gradlew integrationTest
```

### 7. Virtual Threads 적용 (선택)

```yaml
# application.yml에 추가
spring:
  threads:
    virtual:
      enabled: true
```

성능 테스트를 통해 효과를 확인한다.

## 마이그레이션 체크리스트

- [ ] Java 17+ 설치 및 설정
- [ ] Spring Boot 4.0 의존성 업데이트
- [ ] javax → jakarta 패키지 변경
- [ ] RestTemplate 사용 코드 확인 및 교체
- [ ] Deprecated 설정 항목 업데이트
- [ ] 전체 테스트 실행 및 통과
- [ ] Virtual Threads 적용 검토
- [ ] GraalVM 네이티브 이미지 빌드 테스트 (해당 시)
- [ ] 프로덕션 배포 전 성능 테스트

## 참고 자료

- [Spring Framework 7.0 Release Notes](https://github.com/spring-projects/spring-framework/wiki/What's-New-in-Spring-Framework-7.x)
- [Spring Boot 4.0 Release Notes](https://github.com/spring-projects/spring-boot/wiki/Spring-Boot-4.0-Release-Notes)
- [Jakarta EE 10 Specification](https://jakarta.ee/release/10/)
- [Virtual Threads Guide](https://docs.oracle.com/en/java/javase/21/core/virtual-threads.html)
- [Spring Boot Migration Guide](https://github.com/spring-projects/spring-boot/wiki/Spring-Boot-4.0-Migration-Guide)
