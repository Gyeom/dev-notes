---
title: "Spring Boot 3.x GraalVM 네이티브 이미지 빌드 가이드"
date: 2025-11-29
draft: true
tags: ["Spring Boot", "GraalVM", "Native Image", "Java", "Performance"]
categories: ["Backend"]
summary: "Spring Boot 3.x로 GraalVM 네이티브 이미지를 빌드하고 Docker 컨테이너로 실행하는 방법"
---

Spring Boot 3.x는 GraalVM 네이티브 이미지를 공식 지원한다. 네이티브 이미지는 AOT(Ahead-Of-Time) 컴파일로 빠른 시작 시간과 낮은 메모리 사용량을 제공한다. 프로덕션 환경에서 컨테이너 밀도를 높이고 콜드 스타트를 최소화할 수 있다.

## 준비 사항

### 1. GraalVM 설치

```bash
# SDKMAN으로 설치
sdk install java 21.0.1-graal
sdk use java 21.0.1-graal

# 설치 확인
java -version
# GraalVM CE 21.0.1+12.1 (build 21.0.1+12-jvmci-23.1-b15)
```

### 2. Spring Boot 프로젝트 설정

`build.gradle.kts`:

```kotlin
plugins {
    id("org.springframework.boot") version "3.2.0"
    id("io.spring.dependency-management") version "1.1.4"
    id("org.graalvm.buildtools.native") version "0.9.28"
    kotlin("jvm") version "1.9.21"
    kotlin("plugin.spring") version "1.9.21"
}

dependencies {
    implementation("org.springframework.boot:spring-boot-starter-web")
    implementation("org.springframework.boot:spring-boot-starter-actuator")
}

graalvmNative {
    binaries {
        named("main") {
            imageName.set("app")
            buildArgs.add("--verbose")
        }
    }
}
```

## 네이티브 이미지 빌드

### 로컬 빌드

```bash
# 네이티브 이미지 빌드 (5-10분 소요)
./gradlew nativeCompile

# 실행 파일 확인
ls -lh build/native/nativeCompile/
# -rwxr-xr-x  1 user  staff    87M Nov 29 10:00 app

# 실행
./build/native/nativeCompile/app
```

**시작 시간 비교:**
- JVM: ~3초
- Native: ~0.1초

### Docker 빌드

Spring Boot는 Paketo Buildpacks를 통해 네이티브 이미지 Docker 빌드를 지원한다.

```bash
# Docker 네이티브 이미지 빌드
./gradlew bootBuildImage

# 이미지 확인
docker images
# REPOSITORY         TAG       SIZE
# myapp             latest    156MB
```

**이미지 크기 비교:**
- JVM 이미지: ~300MB
- Native 이미지: ~150MB

## 실행 및 테스트

```bash
# 컨테이너 실행
docker run -p 8080:8080 myapp:latest

# 헬스 체크
curl http://localhost:8080/actuator/health
# {"status":"UP"}

# 메모리 사용량 확인
docker stats --no-stream
# CONTAINER  MEM USAGE
# myapp      50MB (JVM: 200MB)
```

## 주의사항

### 리플렉션 설정

네이티브 이미지는 리플렉션을 정적으로 분석한다. 동적 리플렉션이 필요하면 수동 설정이 필요하다.

`src/main/resources/META-INF/native-image/reflect-config.json`:

```json
[
  {
    "name": "com.example.MyClass",
    "allDeclaredFields": true,
    "allDeclaredMethods": true
  }
]
```

Spring Boot 3.x는 대부분의 스프링 컴포넌트를 자동으로 처리한다.

### 지원하지 않는 기능

- CGLIB 프록시 (JDK 동적 프록시만 가능)
- 동적 클래스 로딩
- JVM TI (Java Management Extensions)

**회피 방법:**
- `@Configuration(proxyBeanMethods = false)` 사용
- 인터페이스 기반 프록시로 변경

### 빌드 시간

네이티브 이미지 빌드는 JVM 빌드보다 오래 걸린다.

**빌드 시간:**
- 로컬: 5-10분
- CI/CD: 10-15분

**최적화:**
- CI 캐싱 활용
- 자주 변경되는 코드와 분리
- 개발은 JVM, 프로덕션만 네이티브

## 언제 사용하는가

### 적합한 경우
- 마이크로서비스 (빠른 스케일링)
- 서버리스 (콜드 스타트 최소화)
- CLI 도구
- 리소스 제약 환경

### 부적합한 경우
- 장시간 실행 서비스 (JVM JIT가 더 빠름)
- 동적 리플렉션 다량 사용
- 빌드 시간이 중요한 경우

## 결론

Spring Boot 3.x의 네이티브 이미지 지원은 프로덕션 레디다. 시작 시간과 메모리 사용량이 크게 줄어들어 클라우드 네이티브 환경에서 효과적이다. 다만 빌드 시간과 일부 제약사항을 고려해야 한다.

**다음 단계:**
- Spring AOT 처리 이해하기
- 네이티브 이미지 프로파일링 (GraalVM Native Image Inspector)
- 프로덕션 배포 전략 수립
