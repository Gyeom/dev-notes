---
title: "Docker Compose로 로컬 개발 환경 구성하기"
date: 2025-11-29
draft: false
tags: ["Docker", "Docker Compose", "Spring Boot", "PostgreSQL", "Redis", "개발환경"]
categories: ["개발"]
summary: "Spring Boot + PostgreSQL + Redis 조합으로 로컬 개발 환경을 Docker Compose로 구성하는 모범 사례"
---

로컬에서 Spring Boot 애플리케이션을 개발할 때 PostgreSQL과 Redis를 함께 띄우려면 각각 설치하고 관리해야 한다. Docker Compose를 사용하면 이 모든 것을 코드로 정의하고 한 번에 실행할 수 있다.

## 기본 구조

```yaml
# docker-compose.yml
version: '3.8'

services:
  postgres:
    image: postgres:16-alpine
    container_name: dev-postgres
    environment:
      POSTGRES_DB: myapp
      POSTGRES_USER: dev
      POSTGRES_PASSWORD: dev123
    ports:
      - "5432:5432"
    volumes:
      - postgres-data:/var/lib/postgresql/data
      - ./init.sql:/docker-entrypoint-initdb.d/init.sql
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U dev"]
      interval: 10s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    container_name: dev-redis
    ports:
      - "6379:6379"
    volumes:
      - redis-data:/data
    command: redis-server --appendonly yes
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 3s
      retries: 5

volumes:
  postgres-data:
  redis-data:
```

기본 구성은 간단하다. PostgreSQL과 Redis 컨테이너를 정의하고, 각각의 포트를 호스트에 노출한다. 볼륨을 사용해 데이터를 영구 저장한다.

## Spring Boot 연동

Spring Boot는 호스트에서 실행하고, Docker의 DB만 사용하는 방식을 추천한다. IDE 디버깅과 빠른 재시작이 필요하기 때문이다.

```yaml
# application-local.yml
spring:
  datasource:
    url: jdbc:postgresql://localhost:5432/myapp
    username: dev
    password: dev123

  data:
    redis:
      host: localhost
      port: 6379
```

만약 Spring Boot도 컨테이너로 띄우려면 이렇게 추가한다.

```yaml
services:
  app:
    build: .
    container_name: dev-app
    ports:
      - "8080:8080"
    environment:
      SPRING_DATASOURCE_URL: jdbc:postgresql://postgres:5432/myapp
      SPRING_DATA_REDIS_HOST: redis
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
```

주의할 점은 컨테이너 간 통신에서는 `localhost` 대신 서비스 이름(`postgres`, `redis`)을 사용한다는 것이다.

## 초기 데이터 설정

개발 환경에서는 초기 스키마와 테스트 데이터가 필요하다. PostgreSQL 컨테이너는 `/docker-entrypoint-initdb.d/` 디렉토리의 SQL 파일을 자동 실행한다.

```sql
-- init.sql
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO users (username, email) VALUES
    ('admin', 'admin@example.com'),
    ('user1', 'user1@example.com');
```

이 파일을 볼륨으로 마운트하면 컨테이너 생성 시 자동으로 실행된다.

## 개발 편의 기능

### 환경 변수 파일 분리

민감한 정보는 `.env` 파일로 분리한다.

```bash
# .env
POSTGRES_PASSWORD=dev123
REDIS_PASSWORD=
```

```yaml
services:
  postgres:
    environment:
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
```

`.env` 파일은 `.gitignore`에 추가하고, `.env.example`을 커밋한다.

### 다중 프로파일

개발자마다 다른 설정이 필요할 때는 프로파일을 사용한다.

```yaml
# docker-compose.override.yml (gitignore)
services:
  postgres:
    ports:
      - "15432:5432"  # 다른 포트 사용
```

`docker-compose.override.yml`은 자동으로 병합된다.

### 로그 관리

```yaml
services:
  postgres:
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
```

로그 파일 크기를 제한해 디스크 공간을 절약한다.

## 실전 사용법

```bash
# 모든 서비스 시작
docker-compose up -d

# 로그 확인
docker-compose logs -f postgres

# 특정 서비스만 재시작
docker-compose restart redis

# 볼륨까지 포함해서 전체 삭제
docker-compose down -v

# DB 접속
docker-compose exec postgres psql -U dev -d myapp
```

개발 중에는 `docker-compose up -d`로 DB만 띄워두고, Spring Boot는 IDE에서 실행하는 방식이 가장 편하다.

## 주의사항

**포트 충돌**: 이미 로컬에 PostgreSQL이 설치되어 있다면 포트를 변경한다(`"15432:5432"`).

**볼륨 초기화**: 스키마를 변경했는데 반영이 안 된다면 볼륨을 삭제한다.

```bash
docker-compose down -v
docker-compose up -d
```

**네트워크 이름**: 프로젝트 디렉토리 이름이 네트워크 prefix가 된다. 명시적으로 지정하려면 이렇게 한다.

```yaml
networks:
  default:
    name: myapp-network
```

## 추가 도구 통합

개발 환경에 자주 쓰는 도구들도 추가할 수 있다.

```yaml
services:
  # DB 관리 UI
  pgadmin:
    image: dpage/pgadmin4
    ports:
      - "5050:80"
    environment:
      PGADMIN_DEFAULT_EMAIL: admin@example.com
      PGADMIN_DEFAULT_PASSWORD: admin

  # Redis 관리 UI
  redis-commander:
    image: rediscommander/redis-commander
    ports:
      - "8081:8081"
    environment:
      REDIS_HOSTS: local:redis:6379
```

이제 브라우저에서 DB를 관리할 수 있다.

## 정리

Docker Compose로 로컬 개발 환경을 구성하면 이런 장점이 있다.

- 팀원 간 동일한 환경 보장
- 새 프로젝트 시작이 빠름 (`git clone` 후 `docker-compose up` 한 번)
- 버전 관리가 쉬움 (PostgreSQL 14 → 16 업그레이드는 이미지 태그만 변경)
- 로컬 환경 오염 방지

핵심은 **애플리케이션은 호스트에서, 인프라는 컨테이너로** 분리하는 것이다. 이 방식이 개발 생산성과 컨테이너의 장점을 모두 가져갈 수 있다.
