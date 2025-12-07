# Redis 캐싱 전략

## 이력서 연결

> "Redis Cache-Aside 패턴 적용으로 캐시 Hit Rate 90%+ 달성"
> "Multi-tier 캐시 구성으로 응답 시간 최적화"

---

## 핵심 답변 (STAR)

### Situation (상황)
- 한화솔루션 HEMS, 차량/장비 정보 조회 API
- DB 조회 응답 시간 ~50ms
- 동일 데이터 반복 조회 빈번

### Task (과제)
- API 응답 시간 단축
- DB 부하 감소
- 캐시 일관성 유지

### Action (행동)
1. **Cache-Aside 패턴 적용**
   - 캐시 조회 → 미스 시 DB 조회 → 캐시 저장
   - TTL 30분 설정

2. **이벤트 기반 무효화**
   - 데이터 변경 시 `@TransactionalEventListener`로 캐시 무효화
   - 실시간 일관성 보장

3. **Cache Stampede 방지**
   - 분산 락으로 동시 요청 중 하나만 DB 조회
   - Double-check 패턴 적용

4. **모니터링**
   - Hit/Miss 메트릭 수집
   - Hit Rate 90%+ 목표

### Result (결과)
- 응답 시간: 50ms → 5ms (10배 개선)
- 캐시 Hit Rate: 90%+
- DB 부하 80% 감소

---

## 예상 질문

### Q1: Cache-Aside 패턴이 뭔가요?

**답변:**
가장 널리 사용되는 캐시 패턴이다. 애플리케이션이 캐시를 직접 관리한다.

```kotlin
fun getVehicle(id: String): Vehicle {
    val cacheKey = "vehicle:$id"

    // 1. 캐시 조회
    redisTemplate.opsForValue().get(cacheKey)?.let { return it }

    // 2. 캐시 미스 → DB 조회
    val vehicle = vehicleRepository.findById(id)

    // 3. 캐시에 저장
    redisTemplate.opsForValue().set(cacheKey, vehicle, Duration.ofMinutes(30))

    return vehicle
}
```

**장점**: 필요한 데이터만 캐싱, 구현 단순
**단점**: 첫 요청은 항상 느림(Cache Miss), 캐시-DB 불일치 가능

### Q2: 다른 캐시 패턴과 비교해주세요

**답변:**

| 패턴 | 동작 | 장점 | 단점 |
|------|------|------|------|
| **Cache-Aside** | 읽기: 캐시 → DB | 단순, 필요한 것만 캐싱 | 첫 요청 느림 |
| **Write-Through** | 쓰기: 캐시+DB 동시 | 일관성 보장 | 쓰기 지연 |
| **Write-Behind** | 쓰기: 캐시만 → 비동기 DB | 쓰기 성능 극대화 | 데이터 유실 위험 |

**사용 시점:**
- Cache-Aside: 범용적, 첫 구현
- Write-Through: 읽기 많고 일관성 중요
- Write-Behind: 쓰기 많고 지연 허용 (텔레메트리 데이터)

### Q3: 캐시 무효화는 어떻게 했나요?

**답변:**
두 가지 전략을 조합했다.

**1. TTL 기반**
```kotlin
redisTemplate.opsForValue().set(key, value, Duration.ofMinutes(30))
```
- 일정 시간 후 자동 만료
- 약간의 지연이 허용되는 데이터

**2. 이벤트 기반**
```kotlin
@TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
fun onVehicleUpdated(event: VehicleUpdatedEvent) {
    cacheService.invalidate(event.vehicle.id)
}
```
- 데이터 변경 시 즉시 무효화
- 실시간 일관성이 중요한 데이터

### Q4: Cache Stampede가 뭐고 어떻게 방지했나요?

**답변:**
캐시가 만료되는 순간 다수의 요청이 동시에 DB로 몰리는 현상이다.

```
캐시 만료 → 100개 요청이 동시에 DB 조회 → DB 과부하
```

**해결책: 분산 락 + Double-check**

```kotlin
fun getVehicle(id: String): Vehicle {
    // 캐시 조회
    redisTemplate.opsForValue().get(cacheKey)?.let { return it }

    // 분산 락으로 하나의 요청만 DB 조회
    val lock = lockRegistry.obtain(cacheKey)

    return if (lock.tryLock(100, TimeUnit.MILLISECONDS)) {
        try {
            // Double-check: 락 획득 사이에 다른 요청이 캐시를 채웠을 수 있음
            redisTemplate.opsForValue().get(cacheKey)?.let { return it }

            val vehicle = vehicleRepository.findById(id)
            redisTemplate.opsForValue().set(cacheKey, vehicle)
            vehicle
        } finally {
            lock.unlock()
        }
    } else {
        Thread.sleep(50)
        getVehicle(id)  // 재시도
    }
}
```

### Q5: Multi-tier 캐시란 뭔가요?

**답변:**
여러 계층의 캐시를 조합하는 방식이다.

```
요청 → Local Cache (Caffeine) → Distributed Cache (Redis) → Database
         ~0.01ms                    ~1ms                      ~10ms
```

| 계층 | 저장소 | TTL | 용도 |
|------|--------|-----|------|
| L1 | Caffeine | 5분 | Hot data, 인스턴스별 |
| L2 | Redis | 30분 | Warm data, 공유 |
| L3 | Database | - | Cold data, 원본 |

**주의점: 캐시 일관성**
- 데이터 업데이트 시 모든 인스턴스의 Local Cache 무효화 필요
- Redis Pub/Sub으로 무효화 메시지 전파

---

## 꼬리 질문 대비

### Q: Hit Rate 90%는 어떻게 달성했나요?

**답변:**
1. **적절한 TTL 설정**: 너무 짧으면 Miss 증가, 너무 길면 일관성 문제
2. **캐싱 대상 선정**: 읽기 빈번, 변경 적은 데이터
3. **워밍업**: 서비스 시작 시 자주 조회되는 데이터 미리 캐싱

```kotlin
// 캐싱 적합성 판단
| 기준 | 캐싱 적합 | 캐싱 부적합 |
|------|----------|------------|
| 읽기/쓰기 비율 | 읽기 >> 쓰기 | 쓰기 빈번 |
| 일관성 요구 | 약간의 지연 허용 | 실시간 필수 |
| 데이터 크기 | 작음 (~1KB) | 큼 (>100KB) |
```

### Q: Redis 장애 시 어떻게 대응하나요?

**답변:**
Circuit Breaker 패턴으로 Redis 장애 시 DB로 폴백한다.

```kotlin
fun <T> get(key: String): T? {
    return try {
        circuitBreaker.executeSupplier {
            redisTemplate.opsForValue().get(key) as T?
        }
    } catch (e: Exception) {
        logger.warn("Redis unavailable, skipping cache")
        null  // 캐시 없이 DB 직접 조회
    }
}
```

- 연속 실패 시 Circuit Open → Redis 호출 건너뜀
- DB 직접 조회로 서비스 지속
- Redis 복구 후 자동으로 Circuit Close

### Q: 캐시 키 설계는 어떻게 했나요?

**답변:**
```
{type}:{id}:{version?}

vehicle:123
vehicle:123:v2
user:456:profile
```

- 타입으로 네임스페이스 분리
- ID로 고유 식별
- 필요시 버전 추가 (전체 무효화용)

### Q: 직렬화는 어떻게 했나요?

**답변:**
기본 JDK 직렬화 대신 JSON을 사용했다.

```kotlin
@Configuration
class RedisConfig {
    @Bean
    fun redisTemplate(factory: RedisConnectionFactory): RedisTemplate<String, Any> {
        return RedisTemplate<String, Any>().apply {
            connectionFactory = factory
            keySerializer = StringRedisSerializer()
            valueSerializer = Jackson2JsonRedisSerializer(Any::class.java)
        }
    }
}
```

- 가독성: Redis CLI에서 값 확인 가능
- 호환성: 클래스 변경에 유연
- 크기: JDK 직렬화보다 작음

---

## 관련 개념 정리

| 개념 | 설명 |
|------|------|
| Cache-Aside | 애플리케이션이 캐시를 직접 관리 |
| Write-Through | 쓰기 시 캐시+DB 동시 업데이트 |
| Write-Behind | 캐시에만 쓰고 비동기로 DB 반영 |
| Cache Stampede | 캐시 만료 시 다수 요청이 DB로 몰림 |
| TTL | Time To Live, 캐시 만료 시간 |
| Cache Eviction | 캐시 무효화/제거 |
| Hit Rate | 캐시 적중률 (hits / (hits + misses)) |
| Multi-tier Cache | 여러 계층 캐시 조합 (L1 Local + L2 Distributed) |

---

## 아키텍처 다이어그램

```
                    ┌─────────────────┐
                    │   Application   │
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │  Local Cache    │ ← L1 (Caffeine)
                    │  (~0.01ms)      │    TTL: 5분
                    └────────┬────────┘
                             │ Miss
                    ┌────────▼────────┐
                    │  Redis Cache    │ ← L2 (Distributed)
                    │  (~1ms)         │    TTL: 30분
                    └────────┬────────┘
                             │ Miss
                    ┌────────▼────────┐
                    │   PostgreSQL    │ ← L3 (Database)
                    │  (~10ms)        │    원본 데이터
                    └─────────────────┘
```

---

## 모니터링 지표

```kotlin
@Component
class CacheMetrics(private val meterRegistry: MeterRegistry) {

    fun recordHit(cacheName: String) {
        meterRegistry.counter("cache.hits", "name", cacheName).increment()
    }

    fun recordMiss(cacheName: String) {
        meterRegistry.counter("cache.misses", "name", cacheName).increment()
    }
}
```

**주요 지표:**
- Hit Rate: 80% 이상 목표
- Latency: p99 < 5ms
- Memory Usage: Redis 메모리 사용량
- Eviction Count: 메모리 부족으로 제거된 키 수

---

## 기술 선택과 Trade-off

### 왜 Cache-Aside 패턴을 선택했는가?

**대안 비교:**

| 패턴 | 구현 복잡도 | 일관성 | 첫 요청 | 적합한 상황 |
|------|-------------|--------|--------|-------------|
| **Cache-Aside** | 쉬움 | 수동 관리 | 느림 | 범용적 |
| **Write-Through** | 중간 | 자동 보장 | 느림 | 읽기 위주 |
| **Write-Behind** | 높음 | 지연 | 느림 | 쓰기 위주 |
| **Read-Through** | 중간 | 자동 | 느림 | 조회 집중 |

**Cache-Aside 선택 이유:**
- 가장 널리 사용되고 이해하기 쉬움
- 캐싱할 데이터를 선택적으로 결정 가능
- 기존 코드에 최소한의 변경으로 적용

### 캐시 무효화 전략

| 방식 | 일관성 | 구현 복잡도 | 적합한 데이터 |
|------|--------|-------------|--------------|
| **TTL 만료** | 느슨 | 쉬움 | 약간의 지연 허용 |
| **이벤트 기반** | 강함 | 중간 | 실시간성 필요 |
| **수동 무효화** | 강함 | 쉬움 | 명확한 변경 시점 |

**하이브리드 (TTL + 이벤트) 선택 이유:**
- TTL: 기본 안전망 (이벤트 누락 대비)
- 이벤트: 중요 데이터 실시간 갱신
- 두 가지 조합으로 신뢰성 + 실시간성 확보

### Multi-tier Cache Trade-off

| 계층 | 속도 | 일관성 관리 | 메모리 비용 |
|------|------|-------------|-------------|
| **L1 (Local)** | ~0.01ms | 어려움 | 서버별 |
| **L2 (Redis)** | ~1ms | 쉬움 | 공유 |
| **단일 Redis** | ~1ms | 쉬움 | 공유 |

**Multi-tier 선택 이유:**
- Hot data는 Local에서 처리 (Redis 부하 감소)
- 일관성 문제는 Redis Pub/Sub으로 해결
- 네트워크 라운드트립 감소

**일관성 해결:**
```kotlin
// 데이터 변경 시 모든 인스턴스에 무효화 메시지 전파
redisTemplate.convertAndSend("cache:invalidate", cacheKey)
```

### Cache Stampede 방지

| 방식 | 복잡도 | 효과 | 단점 |
|------|--------|------|------|
| **분산 락** | 중간 | 확실 | 락 대기 |
| **확률적 갱신** | 쉬움 | 중간 | 예측 어려움 |
| **Background Refresh** | 높음 | 좋음 | 추가 리소스 |

**분산 락 + Double-check 선택 이유:**
- 확실한 Stampede 방지
- 락 획득 대기 중 다른 요청이 캐시 채움 확인
- 구현 대비 효과가 좋음

### TTL 설정 Trade-off

```
너무 짧음 (1분): Cache Miss 증가 → DB 부하
너무 김 (24시간): 일관성 저하 → Stale 데이터
적절함 (30분): 균형점 ✓
```

**TTL 30분 선택 이유:**
- 차량/장비 정보: 자주 변경되지 않음
- 이벤트 기반 무효화와 조합
- Hit Rate 90%+ 달성

### 직렬화 방식 Trade-off

| 방식 | 크기 | 가독성 | 호환성 | 속도 |
|------|------|--------|--------|------|
| **JDK Serialization** | 큼 | X | 낮음 | 느림 |
| **JSON (Jackson)** | 중간 | O | 높음 | 중간 |
| **Protobuf** | 작음 | X | 높음 | 빠름 |

**JSON 선택 이유:**
- Redis CLI에서 디버깅 가능
- 클래스 변경에 유연 (필드 추가/삭제)
- 성능 차이보다 운영 편의성 우선

---

## 블로그 링크

- [Redis 캐싱 전략: 실무에서 마주치는 문제와 해결법](https://gyeom.github.io/dev-notes/posts/2023-06-15-redis-caching-strategy-real-world/)

---

*다음: [10-postgresql.md](./10-postgresql.md)*
