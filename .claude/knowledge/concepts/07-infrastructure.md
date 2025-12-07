# 인프라 / 모니터링

## Kubernetes 핵심 개념

### Pod

| 개념 | 설명 |
|------|------|
| **Pod** | 가장 작은 배포 단위, 1개 이상 컨테이너 |
| **Init Container** | 메인 컨테이너 실행 전 초기화 |
| **Sidecar** | 메인 컨테이너와 함께 실행 (로깅, 프록시) |

### 주요 리소스

| 리소스 | 용도 |
|--------|------|
| **Deployment** | 상태 없는 앱 배포, 롤링 업데이트 |
| **StatefulSet** | 상태 있는 앱 (DB), 순차 배포 |
| **DaemonSet** | 모든 노드에 하나씩 (로그 수집기) |
| **Job/CronJob** | 일회성/주기적 작업 |
| **Service** | 파드 접근 추상화 |
| **Ingress** | 외부 HTTP 라우팅 |
| **ConfigMap** | 설정 데이터 |
| **Secret** | 민감 정보 (암호화) |
| **PVC/PV** | 영구 스토리지 |

### 서비스 타입

| 타입 | 설명 |
|------|------|
| **ClusterIP** | 클러스터 내부에서만 접근 (기본) |
| **NodePort** | 노드 포트로 외부 노출 |
| **LoadBalancer** | 클라우드 로드밸런서 연결 |
| **ExternalName** | 외부 DNS 매핑 |

### Probe

```yaml
livenessProbe:    # 컨테이너 재시작 여부 결정
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 30
  periodSeconds: 10

readinessProbe:   # 트래픽 수신 여부 결정
  httpGet:
    path: /ready
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 5

startupProbe:     # 시작 완료 여부 (느린 앱용)
  httpGet:
    path: /health
    port: 8080
  failureThreshold: 30
  periodSeconds: 10
```

### HPA (Horizontal Pod Autoscaler)

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: my-app
  minReplicas: 2
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
```

---

## Docker 최적화

### 멀티스테이지 빌드

```dockerfile
# Build stage
FROM gradle:8-jdk21 AS build
WORKDIR /app
COPY . .
RUN gradle build --no-daemon

# Runtime stage
FROM eclipse-temurin:21-jre-alpine
WORKDIR /app
COPY --from=build /app/build/libs/*.jar app.jar
ENTRYPOINT ["java", "-jar", "app.jar"]
```

### 레이어 캐싱 최적화

```dockerfile
# ❌ 매번 전체 빌드
COPY . .
RUN gradle build

# ✅ 의존성 먼저 복사 (캐시 활용)
COPY build.gradle.kts settings.gradle.kts ./
RUN gradle dependencies --no-daemon
COPY src ./src
RUN gradle build --no-daemon
```

### 이미지 크기 최소화

| 베이스 이미지 | 크기 | 적합한 상황 |
|--------------|------|------------|
| `ubuntu` | ~80MB | 디버깅 필요 |
| `alpine` | ~5MB | 대부분 |
| `distroless` | ~20MB | 보안 중시 |
| `scratch` | 0 | Go 정적 바이너리 |

---

## CI/CD 패턴

### GitOps

```
개발자 → Git Push → CI Pipeline → 이미지 빌드/푸시
                                        ↓
                                  Manifest Git Repo 업데이트
                                        ↓
ArgoCD/FluxCD → 감지 → Kubernetes 클러스터 배포
```

### 배포 전략

| 전략 | 설명 | 장점 | 단점 |
|------|------|------|------|
| **Rolling** | 점진적 교체 | 무중단 | 롤백 느림 |
| **Blue/Green** | 환경 전환 | 즉시 롤백 | 리소스 2배 |
| **Canary** | 일부에만 배포 | 리스크 최소 | 복잡 |
| **A/B Testing** | 사용자 분할 | 실험 가능 | 복잡 |

### GitHub Actions 예시

```yaml
name: CI/CD
on:
  push:
    branches: [main]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Build and push Docker image
        uses: docker/build-push-action@v5
        with:
          push: true
          tags: ghcr.io/${{ github.repository }}:${{ github.sha }}

      - name: Update manifest
        run: |
          sed -i "s|image:.*|image: ghcr.io/${{ github.repository }}:${{ github.sha }}|" k8s/deployment.yaml
          git push
```

---

## LGTM 스택

### 구성요소

| 구성 | 역할 | 설명 |
|------|------|------|
| **L**oki | 로그 | 레이블 기반 로그 저장소 |
| **G**rafana | 시각화 | 통합 대시보드 |
| **T**empo | 트레이싱 | 분산 트레이스 저장소 |
| **M**imir | 메트릭 | Prometheus 호환 장기 저장 |

### 아키텍처

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

### LGTM vs ELK

| 기준 | ELK | LGTM |
|------|-----|------|
| 로그 | Elasticsearch | Loki |
| 시각화 | Kibana | Grafana |
| 메트릭 | 별도 구성 필요 | Mimir (Prometheus 호환) |
| 트레이싱 | 별도 구성 필요 | Tempo |
| 리소스 사용량 | 높음 | 낮음 |
| 쿼리 언어 | 각각 다름 | Grafana에서 통합 |

---

## Observability Three Pillars

```
        Observability
             │
    ┌────────┼────────┐
    ▼        ▼        ▼
  Logs    Metrics   Traces
 (로그)   (메트릭)   (트레이스)
```

| 축 | 설명 | 질문 | 도구 |
|---|------|------|------|
| **Logs** | 이벤트 기록 | 무엇이 발생했는지 | Loki, ELK |
| **Metrics** | 집계 수치 | 얼마나 발생했는지 | Prometheus, Mimir |
| **Traces** | 요청 흐름 | 어디서 시간이 걸렸는지 | Tempo, Jaeger |

### 문제 해결 시나리오

```
1. [Alert] API 응답 시간 p99 > 500ms (Metrics)
2. Grafana에서 느린 요청 확인 (Metrics)
3. Tempo에서 해당 요청의 트레이스 분석 (Traces)
4. DB 쿼리에서 지연 발견
5. Loki에서 해당 시간대 DB 로그 확인 (Logs)
6. 원인: 인덱스 누락 → 해결
```

---

## Micrometer

### 메트릭 타입

| 타입 | 용도 | 예시 |
|------|------|------|
| **Counter** | 누적 카운트 | 처리 건수, 에러 수 |
| **Gauge** | 현재 값 | 커넥션 풀 크기, 큐 길이 |
| **Timer** | 시간 측정 | 응답 시간, 처리 시간 |
| **Distribution Summary** | 값 분포 | 요청 크기, 배치 크기 |

### 커스텀 메트릭 구현

```kotlin
@Component
class OrderMetrics(private val meterRegistry: MeterRegistry) {
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

### Cardinality 폭발

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

## 분산 트레이싱

### Trace 구조

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

### 구현 (Spring Cloud Sleuth + Micrometer Tracing)

```kotlin
@Component
class OrderProcessor(private val tracer: Tracer) {
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

---

## Grafana Alert

### Alert Rule 예시

```yaml
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

### 주요 알림 항목

| 항목 | 조건 | 심각도 |
|------|------|--------|
| Error Rate | > 1% | Critical |
| Response Time p99 | > 500ms | Warning |
| CPU Usage | > 80% | Warning |
| Memory Usage | > 85% | Warning |
| Kafka Lag | > 10000 | Critical |

### 알림 채널

- **Slack**: 개발팀 채널
- **PagerDuty**: On-call 담당자
- **Email**: 요약 리포트

---

## SLI / SLO / SLA

| 개념 | 설명 | 예시 |
|------|------|------|
| **SLI** (Indicator) | 서비스 수준 지표 | p99 응답 시간, 에러율 |
| **SLO** (Objective) | 서비스 수준 목표 | p99 < 200ms, 에러율 < 0.1% |
| **SLA** (Agreement) | 서비스 수준 협약 | 99.9% 가용성 미달 시 크레딧 |

```
SLI (측정) → SLO (목표) → SLA (계약)
```

---

## 메트릭 프레임워크

### RED 메트릭 (Request-oriented)

서비스의 요청 관점 메트릭.

| 메트릭 | 설명 |
|--------|------|
| **R**ate | 초당 요청 수 |
| **E**rrors | 에러율 |
| **D**uration | 응답 시간 |

### USE 메트릭 (Resource-oriented)

시스템 리소스 관점 메트릭.

| 메트릭 | 설명 |
|--------|------|
| **U**tilization | 리소스 사용률 |
| **S**aturation | 대기 중인 작업 |
| **E**rrors | 에러 수 |

---

## 로그 전략

### 로그 레벨

| 레벨 | 용도 | 예시 |
|------|------|------|
| ERROR | 즉시 조치 필요 | 외부 API 실패, DB 연결 실패 |
| WARN | 잠재적 문제 | 재시도 성공, 임계치 근접 |
| INFO | 비즈니스 이벤트 | 주문 생성, 결제 완료 |
| DEBUG | 개발/디버깅용 | 요청/응답 상세 |

### 구조화된 로깅

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

- JSON 포맷으로 출력
- 필드 기반 검색 가능
- Loki에서 LogQL로 쿼리

---

## Prometheus vs InfluxDB

| 기준 | Prometheus | InfluxDB |
|------|-----------|----------|
| 데이터 수집 | Pull (스크래핑) | Push |
| 쿼리 언어 | PromQL | InfluxQL/Flux |
| 고가용성 | 자체 없음 (Thanos/Mimir) | 클러스터 지원 |
| 생태계 | Kubernetes 표준 | IoT에 강점 |

Kubernetes 환경에서는 **Prometheus**가 사실상 표준이다.

---

## 장애 대응

### Incident 대응 프로세스

```
1. Detection (탐지)
   └── 알람 수신, 사용자 보고

2. Triage (분류)
   └── 영향도 평가, 우선순위 결정

3. Response (대응)
   └── On-call 엔지니어 소집, 롤백/완화

4. Remediation (해결)
   └── 근본 원인 파악, 수정 배포

5. Postmortem (회고)
   └── 문서화, 재발 방지책
```

### Runbook 예시

```markdown
## 알람: API Error Rate > 5%

### 증상
- /api/v1/orders 엔드포인트에서 5xx 에러 급증

### 확인 사항
1. Grafana 대시보드 확인
   - 어떤 에러 코드가 많은지 (500, 502, 503, 504)
2. 로그 확인 (Loki)
   - `{app="order-service"} |= "ERROR"`
3. 최근 배포 확인
   - `kubectl rollout history deployment/order-service`

### 조치
1. 롤백: `kubectl rollout undo deployment/order-service`
2. DB 연결 확인: `kubectl exec -it pod -- psql -h db -c "SELECT 1"`
3. 확장: `kubectl scale deployment/order-service --replicas=5`

### 에스컬레이션
- 30분 이내 해결 안 되면 -> 팀 리드 연락
```

### On-call 가이드

| 상황 | 대응 |
|------|------|
| 단일 서비스 다운 | 해당 서비스 재시작, 롤백 |
| DB 연결 실패 | Connection Pool 확인, DB 상태 확인 |
| 메모리 부족 | Pod 재시작, 리소스 증설 |
| Kafka Lag 급증 | Consumer 확장, 처리 로직 확인 |

---

## 성능 튜닝

### JVM 튜닝

```bash
# 기본 설정
JAVA_OPTS="-Xms512m -Xmx1024m"

# G1GC (Java 11+)
JAVA_OPTS="-XX:+UseG1GC -XX:MaxGCPauseMillis=200"

# ZGC (Java 17+, 저지연)
JAVA_OPTS="-XX:+UseZGC"
```

### Kubernetes 리소스 설정

```yaml
resources:
  requests:    # 최소 보장
    memory: "512Mi"
    cpu: "250m"
  limits:      # 최대 허용
    memory: "1Gi"
    cpu: "1000m"
```

**가이드라인:**
- `requests`: 평균 사용량 기준
- `limits`: 피크 시 필요량
- CPU limit 설정 주의 (throttling 발생 가능)

### 부하 테스트

```bash
# k6 예시
k6 run --vus 100 --duration 30s script.js

# Locust 예시
locust -f locustfile.py --headless -u 100 -r 10
```

| 도구 | 특징 |
|------|------|
| **k6** | JavaScript, CLI 친화, 클라우드 연동 |
| **Locust** | Python, 분산 실행 |
| **JMeter** | GUI, 레거시 |
| **Gatling** | Scala, 상세 리포트 |

---

## OpenTelemetry

### 구성요소

| 구성 | 설명 |
|------|------|
| **API** | 계측 인터페이스 |
| **SDK** | API 구현체 |
| **Collector** | 데이터 수집/변환/전송 |

### 장점

- 벤더 중립적
- Traces, Metrics, Logs 통합
- 다양한 백엔드 지원 (Jaeger, Zipkin, Prometheus 등)

### Spring Boot 통합

```yaml
# application.yml
management:
  tracing:
    sampling:
      probability: 1.0
  otlp:
    tracing:
      endpoint: http://collector:4318/v1/traces
```

---

## 관련 Interview 문서

- [16-observability.md](../interview/16-observability.md)

---

*이전: [06-spring-kotlin.md](./06-spring-kotlin.md)*
