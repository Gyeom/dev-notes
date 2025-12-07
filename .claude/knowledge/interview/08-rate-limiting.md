# Rate Limiting 설계

## 이력서 연결

> "Token Bucket 기반 Rate Limiting 구현"
> "분산 환경에서 Redis + Lua를 활용한 원자적 Rate Limiting"

---

## 핵심 답변 (STAR)

### Situation (상황)
- 42dot Vehicle Platform, 외부 API 공개
- 특정 사용자가 과도한 요청으로 서버 부하 유발
- DDoS 공격에 취약

### Task (과제)
- 사용자별 요청 수 제한
- 분산 환경에서 일관된 Rate Limiting
- Burst 트래픽 적절히 허용

### Action (행동)
1. **Token Bucket 알고리즘 선택**
   - Burst 트래픽 허용 (버킷 용량만큼)
   - 메모리 효율적 (토큰 수, 마지막 리필 시간만 저장)

2. **Redis + Lua로 분산 구현**
   - Lua Script로 원자적 연산 보장
   - Race Condition 방지

3. **Spring Cloud Gateway 연동**
   - Gateway 레벨에서 전역 Rate Limiting
   - KeyResolver로 사용자별 구분

4. **HTTP 표준 헤더**
   - `X-RateLimit-Limit`, `X-RateLimit-Remaining`
   - 429 응답 시 `Retry-After` 헤더

### Result (결과)
- 서비스 안정성 확보
- 악의적 사용자 자동 차단
- 클라이언트가 Rate Limit 상태 파악 가능

---

## 예상 질문

### Q1: Rate Limiting이 왜 필요한가요?

**답변:**

| 목적 | 설명 |
|------|------|
| **서비스 보호** | 단일 사용자가 리소스 독점 방지 |
| **DDoS 방어** | 악의적인 대량 요청 차단 |
| **비용 관리** | 클라우드 환경에서 과도한 리소스 사용 방지 |
| **공정성** | 모든 사용자에게 균등한 서비스 제공 |
| **과금 모델** | API 티어별 차등 제한 (Free: 100/분, Pro: 1000/분) |

### Q2: Token Bucket 알고리즘이 뭔가요?

**답변:**
가장 널리 사용되는 Rate Limiting 알고리즘이다.

**동작 원리:**
1. 버킷에 일정 속도로 토큰이 추가된다 (예: 초당 10개)
2. 요청이 오면 토큰을 1개 소비한다
3. 토큰이 없으면 요청을 거부한다
4. 버킷 용량을 초과하면 토큰이 버려진다 (burst 제한)

```kotlin
class TokenBucket(
    private val capacity: Long,      // 버킷 최대 용량
    private val refillRate: Long     // 초당 토큰 추가량
) {
    private var tokens: Double = capacity.toDouble()
    private var lastRefillTime: Long = System.nanoTime()

    @Synchronized
    fun tryConsume(): Boolean {
        refill()
        return if (tokens >= 1) {
            tokens -= 1
            true
        } else {
            false
        }
    }
}
```

**장점**: Burst 트래픽 허용 (버킷 용량만큼), 메모리 효율적
**단점**: 분산 환경에서 동기화 필요

### Q3: 다른 알고리즘과 비교해주세요

**답변:**

| 알고리즘 | 메모리 | Burst 허용 | 정확도 | 구현 복잡도 |
|----------|--------|------------|--------|-------------|
| **Token Bucket** | O(1) | O | 높음 | 중간 |
| **Leaky Bucket** | O(N) | X | 높음 | 중간 |
| **Fixed Window** | O(1) | 경계에서 2배 | 낮음 | 쉬움 |
| **Sliding Window Log** | O(N) | X | 매우 높음 | 중간 |
| **Sliding Window Counter** | O(1) | 일부 | 높음 | 중간 |

**선택 기준:**
- Burst 트래픽 허용 필요 → **Token Bucket**
- 정확한 제한 필요 → **Sliding Window Counter**
- 단순한 구현 필요 → **Fixed Window** (정확도 낮음 감안)

### Q4: 분산 환경에서 어떻게 구현했나요?

**답변:**
Redis + Lua Script로 원자적 연산을 보장했다.

**문제: Race Condition**
```kotlin
// 이 코드는 분산 환경에서 안전하지 않다
val current = redis.get(key)?.toInt() ?: 0
if (current < limit) {
    redis.incr(key)  // 두 서버가 동시에 증가 가능!
    return true
}
```

**해결: Lua Script의 원자성**
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
    return 1  -- 허용
else
    return 0  -- 거부
end
```

Redis의 Lua 스크립트는 **단일 명령처럼 원자적으로 실행**된다.

### Q5: HTTP 응답은 어떻게 설계했나요?

**답변:**
표준 헤더를 사용해서 클라이언트가 Rate Limit 상태를 알 수 있도록 했다.

**정상 응답:**
```http
HTTP/1.1 200 OK
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 95
X-RateLimit-Reset: 1701388800
```

**제한 초과:**
```http
HTTP/1.1 429 Too Many Requests
Retry-After: 60
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 0

{
  "error": "Too Many Requests",
  "message": "Rate limit exceeded. Please retry after 60 seconds."
}
```

| 헤더 | 설명 |
|------|------|
| `X-RateLimit-Limit` | 윈도우당 최대 요청 수 |
| `X-RateLimit-Remaining` | 남은 요청 수 |
| `X-RateLimit-Reset` | 리셋 시점 (Unix timestamp) |
| `Retry-After` | 재시도까지 대기 시간 (초) |

---

## 꼬리 질문 대비

### Q: Fixed Window의 경계 버스트 문제가 뭔가요?

**답변:**
```
        윈도우 1          윈도우 2
    |---------|---------|
              ↑
         경계 시점

윈도우 1 마지막 1초: 100 요청
윈도우 2 처음 1초: 100 요청
→ 2초 동안 200 요청 허용 (제한의 2배!)
```

Sliding Window Counter로 해결 가능:
- 이전 윈도우의 가중치를 반영
- 현재 시점 기준으로 정확한 카운트

### Q: Spring에서 어떤 라이브러리를 사용했나요?

**답변:**
상황에 따라 다른 선택:

| 기준 | Bucket4j | Resilience4j | Spring Cloud Gateway |
|------|----------|--------------|---------------------|
| 알고리즘 | Token Bucket | Sliding Window | Token Bucket |
| 분산 지원 | Redis, Hazelcast | 기본 인메모리 | Redis |
| 사용 시점 | 세밀한 API 제한 | 회복탄력성 전반 | API Gateway 구축 시 |

저희는 **Spring Cloud Gateway + Redis**를 사용했다:
- Gateway 레벨에서 전역 Rate Limiting
- `KeyResolver`로 사용자별/IP별 구분
- Redis 기반 분산 처리

### Q: Redis 장애 시 어떻게 대응하나요?

**답변:**
로컬 인메모리 Rate Limiter로 폴백한다.

```kotlin
fun isAllowedWithFallback(key: String): Boolean {
    return try {
        redisRateLimiter.isAllowed(key)
    } catch (e: RedisConnectionException) {
        logger.warn("Redis unavailable, falling back to local")
        localRateLimiter.isAllowed(key)
    }
}
```

로컬 폴백의 한계:
- 분산 환경에서 각 서버가 독립적으로 카운트
- 실제 제한보다 느슨해질 수 있음
- 하지만 서비스 중단보다는 나음

### Q: 계층별 Rate Limiting이란?

**답변:**
여러 계층에서 다단계로 제한을 적용한다.

```yaml
rate_limits:
  global:           # 전체 시스템 보호
    limit: 10000
    window: 1s
  per_user:         # 사용자별 제한
    free:
      limit: 100
      window: 1m
    pro:
      limit: 1000
      window: 1m
  per_endpoint:     # 엔드포인트별 제한
    /api/search:
      limit: 10
      window: 1m
    /api/export:
      limit: 5
      window: 1h
```

Stripe도 4계층 Rate Limiting을 사용한다:
1. Request Rate Limiter (사용자당 초당 요청 수)
2. Concurrent Request Limiter (동시 요청 수)
3. Fleet Usage Load Shedder (전체 시스템 부하)
4. Worker Utilization Shedder (워커별 부하)

---

## 관련 개념 정리

| 개념 | 설명 |
|------|------|
| Token Bucket | 토큰 기반 Rate Limiting, Burst 허용 |
| Leaky Bucket | 일정 속도로 처리, Burst 불허 |
| Fixed Window | 고정 시간 윈도우별 카운트 |
| Sliding Window | 이동 윈도우로 정확한 카운트 |
| Lua Script | Redis에서 원자적 연산 보장 |
| KeyResolver | 요청을 사용자/IP 등으로 구분 |
| 429 Too Many Requests | Rate Limit 초과 HTTP 상태 코드 |
| Retry-After | 재시도까지 대기 시간 헤더 |

---

## 아키텍처 다이어그램

```
┌─────────────────┐
│     Client      │
└────────┬────────┘
         │
┌────────▼────────┐
│   Load Balancer │
└────────┬────────┘
         │
┌────────▼────────┐
│   API Gateway   │ ← Rate Limiting 적용
│  (Spring Cloud) │
└────────┬────────┘
         │
┌────────▼────────┐     ┌─────────────┐
│   Application   │────▶│    Redis    │
│    (Server 1)   │     │   (Shared)  │
└─────────────────┘     └─────────────┘
┌─────────────────┐            ↑
│   Application   │────────────┘
│    (Server 2)   │
└─────────────────┘
```

---

## 기술 선택과 Trade-off

### 왜 Token Bucket을 선택했는가?

**대안 비교:**

| 알고리즘 | Burst 허용 | 메모리 | 정확도 | 구현 복잡도 |
|----------|------------|--------|--------|-------------|
| **Token Bucket** | O | O(1) | 높음 | 중간 |
| **Leaky Bucket** | X | O(N) | 높음 | 중간 |
| **Fixed Window** | 경계에서 2배 | O(1) | 낮음 | 쉬움 |
| **Sliding Window Log** | X | O(N) | 매우 높음 | 중간 |
| **Sliding Window Counter** | 일부 | O(1) | 높음 | 중간 |

**Token Bucket 선택 이유:**
- Burst 트래픽 허용 필요 (버킷 용량만큼)
- 메모리 효율적 (토큰 수 + 마지막 리필 시간만 저장)
- AWS, Stripe 등 대규모 서비스에서 검증됨

### Redis + Lua vs 로컬 Rate Limiter

| 기준 | 로컬 (인메모리) | Redis + Lua |
|------|----------------|-------------|
| 분산 일관성 | 불가 | 보장 |
| 네트워크 비용 | 없음 | 있음 |
| 장애 영향 | 없음 | Redis 의존 |
| 확장성 | 서버별 독립 | 글로벌 |

**Redis + Lua 선택 이유:**
- API Gateway가 여러 인스턴스로 분산
- 사용자별 글로벌 제한 필요
- Lua Script로 원자성 보장 → Race Condition 방지

### Gateway vs Application Level

| 위치 | 장점 | 단점 |
|------|------|------|
| **API Gateway** | 조기 차단, 단일 지점 | 세밀한 제어 어려움 |
| **Application** | 비즈니스 로직 연동 | 리소스 낭비 |
| **혼합** | 계층적 방어 | 복잡도 증가 |

**Gateway 레벨 선택 이유:**
- 악의적 요청은 빠르게 차단 (리소스 절약)
- 공통 Rate Limiting은 Gateway에서 처리
- 특수 케이스는 Application에서 추가 제한

### 폴백 전략 Trade-off

| 전략 | Redis 장애 시 | 보안 수준 |
|------|--------------|----------|
| **차단** | 서비스 중단 | 높음 |
| **허용** | 무제한 허용 | 낮음 |
| **로컬 폴백** | 느슨한 제한 | 중간 |

**로컬 폴백 선택 이유:**
- 서비스 가용성 우선
- Redis 장애는 드물고 짧음
- 로컬 제한이라도 무제한보다 나음

### HTTP 헤더 표준화 Trade-off

**표준 헤더:**
```
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 95
X-RateLimit-Reset: 1701388800
Retry-After: 60
```

**장점:**
- 클라이언트가 Rate Limit 상태 파악 가능
- 자동 재시도 로직 구현 용이
- 업계 표준 (GitHub, Stripe 등)

**비용:**
- 매 요청마다 헤더 계산
- 응답 크기 약간 증가

**표준 헤더 선택 이유:**
- 클라이언트 개발자 경험 향상
- 불필요한 재시도 감소 → 서버 부하 완화

---

## 블로그 링크

- [Rate Limiting 구현 가이드](https://gyeom.github.io/dev-notes/posts/2024-08-20-rate-limiting-deep-dive/)

---

*다음: [09-redis-caching.md](./09-redis-caching.md)*
