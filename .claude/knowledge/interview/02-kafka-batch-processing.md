# Kafka 대용량 메시지 처리

## 이력서 연결

> "분당 50만 건 데이터 처리 아키텍처 구축"
> "Batch Consumer + Spring JDBC Bulk Insert + @Async Thread Pool 튜닝"

---

## 핵심 답변 (STAR)

### Situation (상황)
- 한화솔루션 HEMS 서비스, IoT 장비 텔레메트리 데이터 수집
- 기존 시스템: 수만 대 장비 처리
- 요구사항: 50만 대 장비로 확장 (10배 이상)
- 각 장비가 1분마다 데이터 전송 → 분당 50만 건

### Task (과제)
- 기존 단건 처리 방식으로는 처리 불가
- Consumer Lag 누적, DB 부하 급증
- 실시간성 유지하면서 대용량 처리 필요

### Action (행동)
1. **Batch Consumer 도입**
   - `spring.kafka.listener.type=batch`
   - `max.poll.records=500` 설정
   - 한 번에 여러 메시지를 가져와 처리

2. **Spring JDBC Bulk Insert**
   - JPA saveAll() 대신 JDBC batchUpdate() 사용
   - 500건씩 묶어서 단일 INSERT 문으로 처리
   - N번 INSERT → 1번 INSERT (네트워크 라운드트립 감소)

3. **@Async Thread Pool 튜닝**
   - CPU 코어 수 기반 스레드 풀 설정
   - I/O bound 작업이므로 코어 * 2 ~ 4배
   - 큐 사이즈, rejection policy 설정

4. **부하 테스트**
   - 시뮬레이터 개발하여 실제 트래픽 재현
   - Grafana로 Consumer Lag, 처리량 모니터링

### Result (결과)
- 분당 50만 건 안정적 처리 달성
- Consumer Lag 0 유지
- DB CPU 사용률 80% → 30% 감소

---

## 예상 질문

### Q1: 왜 Batch Consumer를 선택했나요?

**답변:**
단건 처리의 문제점:
- 매 메시지마다 DB 커넥션 획득/반납
- INSERT 문 N번 실행 (네트워크 오버헤드)
- 컨텍스트 스위칭 비용

Batch Consumer의 장점:
- 여러 메시지를 한 번에 가져와 처리
- DB 작업을 Bulk로 묶을 수 있음
- 처리량(throughput) 대폭 향상

### Q2: batch size는 어떻게 결정했나요?

**답변:**
```
max.poll.records = 500
```

결정 기준:
1. **메모리 제약**: 메시지 크기 × batch size가 힙에 부담 안 되는 수준
2. **처리 시간**: `max.poll.interval.ms` 내에 처리 가능해야 함
3. **DB Bulk Insert 효율**: 500~1000건이 최적 (너무 크면 트랜잭션 롤백 부담)
4. **실험적 튜닝**: 100, 500, 1000으로 테스트 후 500 선택

### Q3: JPA saveAll() 대신 JDBC를 쓴 이유는?

**답변:**

JPA saveAll()의 문제:
```java
// 내부적으로 개별 INSERT 실행
for (Entity e : entities) {
    em.persist(e);  // INSERT 1번
}
```

JDBC Batch의 장점:
```java
// 단일 INSERT 문으로 변환
jdbcTemplate.batchUpdate(
    "INSERT INTO telemetry VALUES (?, ?, ?)",
    batchArgs
);
```

- 네트워크 라운드트립: N번 → 1번
- DB 파싱 비용 감소
- 약 10배 성능 향상 확인

### Q4: @Async는 왜 사용했나요?

**답변:**
Kafka Consumer → DB Insert가 동기적이면:
- Consumer가 DB 응답 대기하는 동안 유휴 상태
- poll() 주기가 늦어져 rebalance 위험

@Async로 분리:
- Consumer는 메시지 수신에 집중
- DB Insert는 별도 스레드에서 비동기 처리
- 단, 순서 보장 필요 시 파티션 단위로 처리

### Q5: 메시지 유실 가능성은 없나요?

**답변:**
Batch 처리 시 유실 방지 전략:

1. **Manual Commit**
   ```java
   @KafkaListener(...)
   public void consume(List<Message> messages, Acknowledgment ack) {
       try {
           bulkInsert(messages);
           ack.acknowledge();  // 성공 시에만 커밋
       } catch (Exception e) {
           // 커밋 안 함 → 재처리
       }
   }
   ```

2. **에러 발생 시**
   - 해당 배치 전체 재처리 (at-least-once)
   - 멱등성 보장 필요 (UPSERT 또는 unique key)

---

## 꼬리 질문 대비

### Q: Consumer Lag이 쌓이면 어떻게 되나요?

**답변:**
- **현상**: 메시지 처리 속도 < 유입 속도
- **영향**: 실시간성 저하, 메모리 증가
- **대응**:
  1. Consumer 인스턴스 스케일아웃 (파티션 수 이하로)
  2. batch size 늘리기
  3. 처리 로직 최적화
  4. 파티션 수 증가 (장기적)

### Q: 파티션 수와 Consumer 수의 관계는?

**답변:**
- 파티션 1개 = 최대 Consumer 1개가 처리
- Consumer 수 > 파티션 수 → 유휴 Consumer 발생
- 권장: 파티션 수 >= Consumer 수
- 예: 파티션 12개, Consumer 4개 → 각 Consumer가 3개 파티션 담당

### Q: max.poll.interval.ms와 session.timeout.ms 차이는?

**답변:**

| 설정 | 의미 | 기본값 |
|------|------|--------|
| `max.poll.interval.ms` | poll() 호출 간 최대 간격 | 5분 |
| `session.timeout.ms` | heartbeat 기반 생존 체크 | 45초 |

- `max.poll.interval.ms` 초과 → Consumer 제외, rebalance
- Batch 처리 시간이 길면 늘려야 함

### Q: exactly-once는 어떻게 보장하나요?

**답변:**
Kafka 자체 exactly-once:
- Producer: `enable.idempotence=true`
- Consumer: `isolation.level=read_committed`
- 트랜잭션 활용

우리 시스템에서는:
- **at-least-once + 멱등성** 조합
- DB unique key로 중복 방지 (UPSERT)
- 더 단순하고 성능 좋음

---

## 관련 개념 정리

| 개념 | 설명 |
|------|------|
| Consumer Group | 같은 group.id를 공유하는 Consumer 집합, 파티션을 분배받음 |
| Rebalance | Consumer 추가/제거 시 파티션 재할당 |
| Offset | 파티션 내 메시지 위치, Consumer가 어디까지 읽었는지 |
| Lag | 최신 offset - Consumer offset, 처리 지연 정도 |
| Commit | Consumer가 처리 완료한 offset을 Kafka에 기록 |
| Partition | 토픽을 나눈 단위, 병렬 처리의 기본 단위 |

### Kafka 설정 요약

```yaml
spring:
  kafka:
    consumer:
      group-id: telemetry-consumer
      auto-offset-reset: earliest
      enable-auto-commit: false  # Manual commit
      max-poll-records: 500
    listener:
      type: batch
      ack-mode: manual
```

---

## 아키텍처 다이어그램

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  IoT 장비   │────▶│   Kafka     │────▶│  Consumer   │
│  (50만대)   │     │  (12 파티션)│     │  (4 인스턴스)│
└─────────────┘     └─────────────┘     └──────┬──────┘
                                               │
                                         Batch (500건)
                                               │
                                               ▼
                                        ┌─────────────┐
                                        │ PostgreSQL  │
                                        │ Bulk Insert │
                                        └─────────────┘
```

---

## 기술 선택과 Trade-off

### 왜 Batch Consumer를 선택했는가?

**대안 비교:**

| 방식 | 처리량 | 구현 복잡도 | 에러 핸들링 | 순서 보장 |
|------|--------|-------------|-------------|----------|
| **단건 처리** | 낮음 | 쉬움 | 쉬움 | 완벽 |
| **Batch Consumer** | 높음 | 중간 | 복잡 | 파티션 내 |
| **Parallel Consumer** | 매우 높음 | 높음 | 복잡 | 보장 안 됨 |

**Batch Consumer 선택 이유:**
- 단건 처리: 분당 50만 건 불가능 (N번 DB 라운드트립)
- Parallel Consumer: 순서 보장이 필요한 텔레메트리 데이터에 부적합
- **Batch Consumer가 처리량과 순서 보장의 균형점**

### JPA saveAll() vs JDBC Batch Update

**Trade-off 비교:**

| 기준 | JPA saveAll() | JDBC Batch |
|------|---------------|------------|
| 개발 생산성 | 높음 | 낮음 |
| 성능 | 낮음 | 높음 |
| 트랜잭션 관리 | 자동 | 수동 |
| 엔티티 영속성 | O | X |
| SQL 최적화 | 불가 | 가능 |

**JDBC Batch 선택 이유:**
- 대용량 처리에서 성능이 10배 이상 차이
- 텔레메트리 데이터는 INSERT Only → 영속성 관리 불필요
- Multi-row INSERT로 추가 최적화 가능

### max.poll.records 설정 Trade-off

```
100건: 네트워크 오버헤드 증가, 안정적
500건: 균형점 ✓
1000건: 처리 시간 길어져 rebalance 위험
```

**500건 선택 이유:**
- 메시지당 ~2KB × 500 = ~1MB → 힙 부담 적음
- 처리 시간 ~500ms → `max.poll.interval.ms` (5분) 대비 충분
- Bulk Insert 효율 최적 구간 (100~1000건)

### 비동기 처리(@Async) Trade-off

| 기준 | 동기 처리 | 비동기 처리 |
|------|----------|------------|
| 순서 보장 | 완벽 | 복잡 |
| Consumer Lag | 쌓일 위험 | 낮음 |
| 에러 추적 | 쉬움 | 어려움 |
| 리소스 사용 | 비효율 | 효율적 |

**비동기 선택 이유:**
- Consumer가 DB 응답 대기 중 idle → 비효율
- 파티션 단위로 처리하면 순서 보장 가능
- 텔레메트리 데이터는 약간의 순서 역전 허용

### 멱등성 보장 전략

**대안:**
1. **DB Unique Key + UPSERT**: 구현 단순, DB 부하
2. **Redis 중복 체크**: 빠름, 추가 인프라
3. **Kafka 트랜잭션**: 복잡, 성능 저하

**UPSERT 선택 이유:**
- 추가 인프라 없이 PostgreSQL만으로 해결
- 중복 발생 빈도 낮음 (정상 상황에서 거의 없음)
- 구현과 운영 단순화

---

## 블로그 링크

- [Kafka 대용량 메시지 처리](https://gyeom.github.io/dev-notes/posts/2023-12-08-kafka-high-volume-processing/)

---

*다음: [03-kafka-dlt-dlq.md](./03-kafka-dlt-dlq.md)*
