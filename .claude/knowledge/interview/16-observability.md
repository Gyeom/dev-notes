# Observability (LGTM 스택)

## 이력서 연결

> "LGTM 스택 기반 Observability 구축"
> "Micrometer 커스텀 메트릭, Grafana Alert"

---

## 핵심 답변 (STAR)

### Situation (상황)
- 42dot Vehicle Platform, 마이크로서비스 아키텍처
- 분산 시스템에서 문제 원인 파악 어려움
- 기존 로그 기반 모니터링의 한계

### Task (과제)
- 시스템 전반의 가시성 확보
- 문제 발생 시 빠른 원인 파악
- 선제적 알림 체계 구축

### Action (행동)
1. **LGTM 스택 구축**
   - **L**oki: 로그 수집
   - **G**rafana: 시각화
   - **T**empo: 분산 트레이싱
   - **M**imir (Prometheus): 메트릭

2. **Micrometer 커스텀 메트릭**
   - 비즈니스 메트릭 정의 (처리량, 지연 시간)
   - 태그 기반 다차원 분석

3. **Grafana Alert 설정**
   - 임계치 기반 알림
   - Slack/Email 연동

### Result (결과)
- 문제 발생 시 평균 해결 시간 50% 단축
- 선제적 이상 탐지로 장애 예방
- 데이터 기반 의사결정 가능

---

## 예상 질문

### Q1: Observability의 세 가지 축(Three Pillars)은?

**답변:**

```
        Observability
             │
    ┌────────┼────────┐
    ▼        ▼        ▼
  Logs    Metrics   Traces
 (로그)   (메트릭)   (트레이스)
```

| 축 | 설명 | 도구 |
|---|------|------|
| **Logs** | 이벤트 기록, 무엇이 발생했는지 | Loki, ELK |
| **Metrics** | 집계 수치, 얼마나 발생했는지 | Prometheus, Mimir |
| **Traces** | 요청 흐름, 어디서 시간이 걸렸는지 | Tempo, Jaeger |

**예시 시나리오:**
```
1. [Alert] API 응답 시간 p99 > 500ms (Metrics)
2. Grafana에서 느린 요청 확인 (Metrics)
3. Tempo에서 해당 요청의 트레이스 분석 (Traces)
4. DB 쿼리에서 지연 발견
5. Loki에서 해당 시간대 DB 로그 확인 (Logs)
6. 원인: 인덱스 누락 → 해결
```

### Q2: LGTM 스택을 선택한 이유는?

**답변:**

| 스택 | ELK | LGTM |
|------|-----|------|
| 로그 | Elasticsearch | Loki |
| 시각화 | Kibana | Grafana |
| 메트릭 | 별도 구성 필요 | Mimir (Prometheus 호환) |
| 트레이싱 | 별도 구성 필요 | Tempo |
| 리소스 사용량 | 높음 | 낮음 |
| 쿼리 언어 | 각각 다름 | Grafana에서 통합 |

**선택 이유:**
1. **통합 대시보드**: Grafana에서 로그/메트릭/트레이스 모두 조회
2. **리소스 효율**: Loki는 인덱싱 없이 로그 저장 (비용 절감)
3. **Prometheus 호환**: 기존 Prometheus 쿼리 그대로 사용
4. **Kubernetes 친화적**: Helm 차트로 쉬운 배포

### Q3: Micrometer 커스텀 메트릭은 어떻게 구현했나요?

**답변:**

```kotlin
@Component
class OrderMetrics(
    private val meterRegistry: MeterRegistry
) {
    // Counter: 주문 처리 건수
    fun incrementOrderCount(status: String) {
        meterRegistry.counter(
            "orders.processed.total",
            "status", status  // 태그
        ).increment()
    }

    // Timer: 주문 처리 시간
    fun recordProcessingTime(duration: Duration) {
        meterRegistry.timer("orders.processing.time")
            .record(duration)
    }

    // Gauge: 대기 중인 주문 수
    fun registerPendingOrders(pendingSupplier: () -> Int) {
        meterRegistry.gauge(
            "orders.pending.count",
            this,
            { pendingSupplier().toDouble() }
        )
    }
}
```

**메트릭 타입:**

| 타입 | 용도 | 예시 |
|------|------|------|
| Counter | 누적 카운트 | 처리 건수, 에러 수 |
| Gauge | 현재 값 | 커넥션 풀 크기, 큐 길이 |
| Timer | 시간 측정 | 응답 시간, 처리 시간 |
| Distribution Summary | 값 분포 | 요청 크기, 배치 크기 |

### Q4: Grafana Alert는 어떻게 설정했나요?

**답변:**

```yaml
# Grafana Alert Rule 예시
apiVersion: 1
groups:
  - name: api-alerts
    rules:
      - alert: HighErrorRate
        expr: |
          sum(rate(http_server_requests_seconds_count{status=~"5.."}[5m]))
          /
          sum(rate(http_server_requests_seconds_count[5m]))
          > 0.01
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "High error rate detected"
          description: "Error rate is {{ $value | humanizePercentage }}"
```

**알림 채널:**
- Slack: 개발팀 채널
- PagerDuty: On-call 담당자
- Email: 요약 리포트

**주요 알림 항목:**
| 항목 | 조건 | 심각도 |
|------|------|--------|
| Error Rate | > 1% | Critical |
| Response Time p99 | > 500ms | Warning |
| CPU Usage | > 80% | Warning |
| Memory Usage | > 85% | Warning |
| Kafka Lag | > 10000 | Critical |

### Q5: 분산 트레이싱은 어떻게 구현했나요?

**답변:**
Spring Cloud Sleuth + Micrometer Tracing을 사용했다.

```kotlin
// 자동으로 Trace ID 전파
// HTTP 요청 → Kafka 메시지 → 다른 서비스

// 수동 span 생성 시
@Component
class OrderProcessor(
    private val tracer: Tracer
) {
    fun processOrder(order: Order) {
        val span = tracer.nextSpan()
            .name("process-order")
            .tag("orderId", order.id)
            .start()

        try {
            Tracer.SpanInScope(span).use {
                // 처리 로직
            }
        } finally {
            span.end()
        }
    }
}
```

**Trace 구조:**
```
[Request] trace_id: abc123
    │
    ├─ [API Gateway] span_id: 001
    │       │
    │       ├─ [Order Service] span_id: 002
    │       │       │
    │       │       └─ [DB Query] span_id: 003
    │       │
    │       └─ [Payment Service] span_id: 004
    │
    └─ [Kafka Producer] span_id: 005
```

Tempo에서 trace_id로 전체 요청 흐름을 시각화한다.

---

## 꼬리 질문 대비

### Q: SLI/SLO/SLA 개념을 설명해주세요

**답변:**

| 개념 | 설명 | 예시 |
|------|------|------|
| **SLI** (Indicator) | 서비스 수준 지표 | p99 응답 시간, 에러율 |
| **SLO** (Objective) | 서비스 수준 목표 | p99 < 200ms, 에러율 < 0.1% |
| **SLA** (Agreement) | 서비스 수준 협약 | 99.9% 가용성 미달 시 크레딧 |

```
SLI (측정) → SLO (목표) → SLA (계약)
```

**우리 프로젝트 SLO:**
- API 가용성: 99.9%
- p99 응답 시간: < 200ms
- 에러율: < 0.1%

### Q: 로그 레벨 전략은?

**답변:**

| 레벨 | 용도 | 예시 |
|------|------|------|
| ERROR | 즉시 조치 필요 | 외부 API 실패, DB 연결 실패 |
| WARN | 잠재적 문제 | 재시도 성공, 임계치 근접 |
| INFO | 비즈니스 이벤트 | 주문 생성, 결제 완료 |
| DEBUG | 개발/디버깅용 | 요청/응답 상세 |

```kotlin
log.error("Payment failed", ex) {
    "orderId" to orderId
    "amount" to amount
}

log.info("Order created") {
    "orderId" to order.id
    "userId" to order.userId
}
```

**구조화된 로깅:**
- JSON 포맷으로 출력
- 필드 기반 검색 가능
- Loki에서 LogQL로 쿼리

### Q: Prometheus vs InfluxDB 차이는?

**답변:**

| 기준 | Prometheus | InfluxDB |
|------|-----------|----------|
| 데이터 수집 | Pull (스크래핑) | Push |
| 쿼리 언어 | PromQL | InfluxQL/Flux |
| 고가용성 | 자체 없음 (Thanos/Mimir) | 클러스터 지원 |
| 생태계 | Kubernetes 표준 | IoT에 강점 |

Kubernetes 환경에서는 **Prometheus**가 사실상 표준이다.

### Q: Cardinality 폭발 문제는?

**답변:**
태그 값의 조합이 너무 많아지면 메트릭 저장소가 폭발한다.

```kotlin
// ❌ 위험: userId는 수백만 개
meterRegistry.counter("api.requests", "userId", userId)

// ✅ 안전: 제한된 값
meterRegistry.counter("api.requests", "userType", userType)
meterRegistry.counter("api.requests", "endpoint", endpoint)
```

**가이드라인:**
- 태그 값은 유한해야 함 (최대 수백 개)
- ID 값은 태그로 사용 금지
- 필요하면 히스토그램으로 대체

---

## 관련 개념 정리

| 개념 | 설명 |
|------|------|
| LGTM | Loki, Grafana, Tempo, Mimir 스택 |
| Micrometer | Java 애플리케이션 메트릭 라이브러리 |
| PromQL | Prometheus 쿼리 언어 |
| LogQL | Loki 쿼리 언어 |
| Span | 분산 트레이싱의 단위 작업 |
| Trace | 여러 Span으로 구성된 요청 흐름 |
| Cardinality | 태그 값의 고유 조합 수 |
| SLI/SLO/SLA | 서비스 수준 지표/목표/협약 |

---

## 아키텍처 다이어그램

```
┌─────────────────────────────────────────────────────────────┐
│                      Applications                           │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │  Service A  │  │  Service B  │  │  Service C  │         │
│  │ (Micrometer)│  │ (Micrometer)│  │ (Micrometer)│         │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘         │
└─────────┼────────────────┼────────────────┼─────────────────┘
          │                │                │
          ▼                ▼                ▼
┌─────────────────────────────────────────────────────────────┐
│                    Observability Stack                       │
│                                                              │
│  ┌───────────┐   ┌───────────┐   ┌───────────┐              │
│  │   Mimir   │   │   Tempo   │   │   Loki    │              │
│  │ (Metrics) │   │ (Traces)  │   │  (Logs)   │              │
│  └─────┬─────┘   └─────┬─────┘   └─────┬─────┘              │
│        │               │               │                     │
│        └───────────────┼───────────────┘                     │
│                        │                                     │
│                 ┌──────▼──────┐                              │
│                 │   Grafana   │                              │
│                 │ (Dashboard) │                              │
│                 └──────┬──────┘                              │
│                        │                                     │
│                 ┌──────▼──────┐                              │
│                 │   Alerting  │ → Slack, PagerDuty           │
│                 └─────────────┘                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 주요 메트릭 체크리스트

**RED 메트릭 (Request-oriented)**
- **R**ate: 초당 요청 수
- **E**rrors: 에러율
- **D**uration: 응답 시간

**USE 메트릭 (Resource-oriented)**
- **U**tilization: 리소스 사용률
- **S**aturation: 대기 중인 작업
- **E**rrors: 에러 수

---

*다음: [17-problem-solving.md](./17-problem-solving.md)*
