---
title: "Redis 캐싱 전략: 실무에서 마주치는 문제와 해결법"
date: 2025-12-05
draft: false
tags: ["Redis", "Cache", "Spring Boot", "성능최적화"]
categories: ["Backend"]
summary: "Cache-Aside, Write-Through, Write-Behind 패턴과 Multi-tier 캐시 구성, Cache Stampede 방지 및 Circuit Breaker 전략을 실무 관점에서 정리한다."
---

## 왜 캐싱인가

데이터베이스 조회는 비용이 크다. 네트워크 왕복, 디스크 I/O, 쿼리 파싱 등 여러 단계를 거친다. 자주 조회되는 데이터를 메모리에 캐싱하면 응답 시간을 수십 ms에서 수 ms로 줄일 수 있다.

하지만 캐싱은 단순히 "Redis에 넣으면 끝"이 아니다. 캐시 일관성, 무효화 전략, 장애 대응까지 고려해야 한다.

---

## 캐시 패턴

### Cache-Aside (Lazy Loading)

가장 널리 사용되는 패턴이다. 애플리케이션이 캐시를 직접 관리한다.

```kotlin
@Service
class VehicleService(
    private val vehicleRepository: VehicleRepository,
    private val redisTemplate: RedisTemplate<String, Vehicle>
) {
    fun getVehicle(id: String): Vehicle {
        val cacheKey = "vehicle:$id"

        // 1. 캐시 조회
        redisTemplate.opsForValue().get(cacheKey)?.let { return it }

        // 2. 캐시 미스 → DB 조회
        val vehicle = vehicleRepository.findById(id)
            .orElseThrow { NotFoundException("Vehicle not found: $id") }

        // 3. 캐시에 저장
        redisTemplate.opsForValue().set(cacheKey, vehicle, Duration.ofMinutes(30))

        return vehicle
    }
}
```

**장점**: 필요한 데이터만 캐싱, 구현이 단순함
**단점**: 첫 요청은 항상 느림(Cache Miss), 캐시와 DB 불일치 가능

### Write-Through

쓰기 시 캐시와 DB를 동시에 업데이트한다.

```kotlin
@Service
class VehicleService(
    private val vehicleRepository: VehicleRepository,
    private val redisTemplate: RedisTemplate<String, Vehicle>
) {
    @Transactional
    fun updateVehicle(id: String, command: UpdateVehicleCommand): Vehicle {
        val vehicle = vehicleRepository.findById(id)
            .orElseThrow { NotFoundException("Vehicle not found: $id") }

        vehicle.update(command)

        // DB 저장
        val saved = vehicleRepository.save(vehicle)

        // 캐시도 함께 업데이트
        val cacheKey = "vehicle:$id"
        redisTemplate.opsForValue().set(cacheKey, saved, Duration.ofMinutes(30))

        return saved
    }
}
```

**장점**: 캐시와 DB 일관성 유지
**단점**: 쓰기 지연 증가, 읽히지 않을 데이터도 캐싱

### Write-Behind (Write-Back)

쓰기를 캐시에만 하고, 비동기로 DB에 반영한다.

```kotlin
@Service
class TelemetryService(
    private val redisTemplate: RedisTemplate<String, Telemetry>,
    private val telemetryRepository: TelemetryRepository
) {
    // 캐시에만 쓰기 (빠름)
    fun saveTelemetry(telemetry: Telemetry) {
        val cacheKey = "telemetry:${telemetry.deviceId}:latest"
        redisTemplate.opsForValue().set(cacheKey, telemetry)

        // 배치 처리를 위해 목록에 추가
        redisTemplate.opsForList().rightPush("telemetry:pending", telemetry)
    }

    // 주기적으로 DB에 반영
    @Scheduled(fixedDelay = 5000)
    fun flushToDatabase() {
        val pending = mutableListOf<Telemetry>()

        while (true) {
            val telemetry = redisTemplate.opsForList()
                .leftPop("telemetry:pending") ?: break
            pending.add(telemetry)
        }

        if (pending.isNotEmpty()) {
            telemetryRepository.saveAll(pending)
        }
    }
}
```

**장점**: 쓰기 성능 극대화, 배치 처리로 DB 부하 감소
**단점**: 데이터 유실 위험, 구현 복잡도 증가

---

## Multi-tier 캐시

Redis만으로 부족할 때가 있다. 네트워크 왕복 시간(~1ms)도 아끼고 싶다면 Local Cache를 추가한다.

```
요청 → Local Cache (Caffeine) → Distributed Cache (Redis) → Database
         ~0.01ms                    ~1ms                      ~10ms
```

### 구현

```kotlin
@Configuration
class CacheConfig {

    @Bean
    fun cacheManager(redisConnectionFactory: RedisConnectionFactory): CacheManager {
        val caffeine = CaffeineCacheManager().apply {
            setCaffeine(
                Caffeine.newBuilder()
                    .maximumSize(1000)
                    .expireAfterWrite(Duration.ofMinutes(5))
            )
        }

        val redis = RedisCacheManager.builder(redisConnectionFactory)
            .cacheDefaults(
                RedisCacheConfiguration.defaultCacheConfig()
                    .entryTtl(Duration.ofMinutes(30))
            )
            .build()

        return CompositeCacheManager(caffeine, redis)
    }
}
```

### 계층별 역할

| 계층 | 저장소 | TTL | 용도 |
|------|--------|-----|------|
| L1 | Caffeine | 5분 | Hot data, 인스턴스별 |
| L2 | Redis | 30분 | Warm data, 공유 |
| L3 | Database | - | Cold data, 원본 |

### 주의점: 캐시 일관성

Multi-tier에서 가장 어려운 문제는 일관성이다. 데이터가 업데이트되면 모든 인스턴스의 Local Cache를 무효화해야 한다.

```kotlin
@Service
class VehicleCacheService(
    private val redisTemplate: RedisTemplate<String, String>,
    private val localCache: Cache
) {
    // Redis Pub/Sub으로 캐시 무효화 전파
    fun invalidate(vehicleId: String) {
        // Local Cache 무효화
        localCache.evict("vehicle:$vehicleId")

        // 다른 인스턴스에 무효화 메시지 전파
        redisTemplate.convertAndSend("cache:invalidate", "vehicle:$vehicleId")
    }

    // 무효화 메시지 수신
    @EventListener
    fun onCacheInvalidate(message: CacheInvalidateMessage) {
        localCache.evict(message.key)
    }
}
```

---

## 캐시 무효화 전략

"컴퓨터 과학에서 어려운 두 가지: 캐시 무효화와 이름 짓기" - Phil Karlton

### TTL 기반

가장 단순하다. 일정 시간 후 자동 만료.

```kotlin
redisTemplate.opsForValue().set(key, value, Duration.ofMinutes(30))
```

**적합한 경우**: 약간의 지연이 허용되는 데이터 (ex: 통계, 집계)

### 이벤트 기반

데이터 변경 시 즉시 무효화.

```kotlin
@Service
class VehicleService(
    private val vehicleRepository: VehicleRepository,
    private val cacheService: VehicleCacheService,
    private val eventPublisher: ApplicationEventPublisher
) {
    @Transactional
    fun updateVehicle(id: String, command: UpdateVehicleCommand): Vehicle {
        val vehicle = vehicleRepository.findById(id)
            .orElseThrow { NotFoundException("Vehicle not found: $id") }

        vehicle.update(command)
        val saved = vehicleRepository.save(vehicle)

        // 이벤트 발행 → 캐시 무효화
        eventPublisher.publishEvent(VehicleUpdatedEvent(saved))

        return saved
    }
}

@Component
class VehicleCacheInvalidator(
    private val cacheService: VehicleCacheService
) {
    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    fun onVehicleUpdated(event: VehicleUpdatedEvent) {
        cacheService.invalidate(event.vehicle.id)
    }
}
```

**적합한 경우**: 실시간 일관성이 중요한 데이터

### 버전 기반

캐시 키에 버전을 포함시킨다.

```kotlin
@Service
class ConfigService(
    private val redisTemplate: RedisTemplate<String, Config>,
    private val configRepository: ConfigRepository
) {
    private var version: Long = System.currentTimeMillis()

    fun getConfig(key: String): Config {
        val cacheKey = "config:$key:v$version"

        redisTemplate.opsForValue().get(cacheKey)?.let { return it }

        val config = configRepository.findByKey(key)
        redisTemplate.opsForValue().set(cacheKey, config)

        return config
    }

    // 버전 변경 → 모든 캐시 자동 무효화
    fun refreshAll() {
        version = System.currentTimeMillis()
    }
}
```

**적합한 경우**: 설정 데이터처럼 한 번에 전체 갱신이 필요한 경우

---

## 캐시 장애 대응

### Cache Stampede 방지

캐시가 만료되는 순간 다수의 요청이 DB로 몰리는 현상.

```kotlin
@Service
class VehicleService(
    private val vehicleRepository: VehicleRepository,
    private val redisTemplate: RedisTemplate<String, Vehicle>,
    private val lockRegistry: LockRegistry
) {
    fun getVehicle(id: String): Vehicle {
        val cacheKey = "vehicle:$id"

        redisTemplate.opsForValue().get(cacheKey)?.let { return it }

        // 분산 락으로 하나의 요청만 DB 조회
        val lock = lockRegistry.obtain(cacheKey)

        return if (lock.tryLock(100, TimeUnit.MILLISECONDS)) {
            try {
                // Double-check: 락 획득 사이에 다른 요청이 캐시를 채웠을 수 있음
                redisTemplate.opsForValue().get(cacheKey)?.let { return it }

                val vehicle = vehicleRepository.findById(id)
                    .orElseThrow { NotFoundException("Vehicle not found: $id") }

                redisTemplate.opsForValue().set(cacheKey, vehicle, Duration.ofMinutes(30))
                vehicle
            } finally {
                lock.unlock()
            }
        } else {
            // 락 획득 실패 → 잠시 후 재시도
            Thread.sleep(50)
            getVehicle(id)
        }
    }
}
```

### Circuit Breaker

Redis 장애 시 DB로 폴백.

```kotlin
@Service
class ResilientCacheService(
    private val redisTemplate: RedisTemplate<String, Any>,
    private val circuitBreakerRegistry: CircuitBreakerRegistry
) {
    private val circuitBreaker = circuitBreakerRegistry.circuitBreaker("redis")

    fun <T> get(key: String, fallback: () -> T): T? {
        return try {
            circuitBreaker.executeSupplier {
                redisTemplate.opsForValue().get(key) as T?
            }
        } catch (e: Exception) {
            logger.warn("Redis unavailable, skipping cache: ${e.message}")
            null // 캐시 없이 진행
        }
    }
}
```

---

## 실무 체크리스트

### 캐싱 대상 선정

| 기준 | 캐싱 적합 | 캐싱 부적합 |
|------|----------|------------|
| 읽기/쓰기 비율 | 읽기 >> 쓰기 | 쓰기 빈번 |
| 일관성 요구 | 약간의 지연 허용 | 실시간 필수 |
| 데이터 크기 | 작음 (~1KB) | 큼 (>100KB) |
| 조회 패턴 | 특정 키로 반복 조회 | 랜덤 조회 |

### 모니터링 지표

```kotlin
@Component
class CacheMetrics(
    private val meterRegistry: MeterRegistry
) {
    fun recordHit(cacheName: String) {
        meterRegistry.counter("cache.hits", "name", cacheName).increment()
    }

    fun recordMiss(cacheName: String) {
        meterRegistry.counter("cache.misses", "name", cacheName).increment()
    }
}

// Hit Rate = hits / (hits + misses)
// 목표: 80% 이상
```

---

## 정리

| 전략 | 사용 시점 | 주의점 |
|------|----------|--------|
| Cache-Aside | 범용적, 첫 구현 | 첫 요청 느림, 일관성 |
| Write-Through | 읽기 많고 일관성 중요 | 쓰기 지연 |
| Write-Behind | 쓰기 많고 지연 허용 | 데이터 유실 위험 |
| Multi-tier | 극한의 성능 필요 | 일관성 관리 복잡 |

캐싱은 성능 최적화의 핵심이지만, 복잡도를 높인다. 먼저 캐싱 없이 최적화(인덱스, 쿼리 튜닝)를 시도하고, 그래도 부족할 때 캐싱을 도입하는 것이 좋다.
