---
title: "About"
layout: "single"
url: "/about/"
summary: "김대겸 | Backend Engineer"
hideMeta: true
hideFooter: true
---

{{< rawhtml >}}
<style>
.resume-container {
  max-width: 900px;
  margin: 0 auto;
}
.resume-header {
  display: flex;
  align-items: flex-start;
  gap: 2.5rem;
  margin-bottom: 2.5rem;
  padding: 2rem;
  background: var(--code-bg);
  border-radius: 12px;
}
.profile-img {
  width: 180px;
  height: 180px;
  border-radius: 12px;
  object-fit: cover;
  flex-shrink: 0;
}
.resume-header-text { flex: 1; }
.resume-header-text h1 {
  margin: 0 0 0.25rem 0;
  font-size: 2rem;
}
.resume-header .subtitle {
  color: var(--secondary);
  font-size: 1.15rem;
  margin-bottom: 1rem;
  font-weight: 500;
}
.resume-header .intro {
  line-height: 1.7;
  margin-bottom: 1.25rem;
  font-size: 0.95rem;
}
.contact-row {
  display: flex;
  gap: 1.5rem;
  align-items: center;
  font-size: 0.9rem;
}
.contact-row a {
  color: var(--primary);
  text-decoration: none;
}
.contact-row a:hover { text-decoration: underline; }
@media (max-width: 640px) {
  .resume-header {
    flex-direction: column;
    align-items: center;
    text-align: center;
    padding: 1.5rem;
  }
  .profile-img { width: 140px; height: 140px; }
  .contact-row { justify-content: center; }
}

.section-title {
  border-bottom: 2px solid var(--primary);
  padding-bottom: 0.5rem;
  margin-top: 2.5rem;
}

.company-header { margin-top: 2rem; }
.company-header h3 { margin-bottom: 0.25rem; }
.company-meta { color: #666; margin-bottom: 0.5rem; }
.company-desc { color: #888; font-size: 0.95rem; margin-bottom: 1rem; }

.project {
  background: var(--code-bg);
  border-radius: 8px;
  padding: 1.25rem;
  margin: 1rem 0;
}
.project-title { font-weight: 600; margin-bottom: 0.75rem; }
.project-subtitle { color: #888; font-size: 0.9rem; margin-bottom: 1rem; }

.achievement { margin: 0.75rem 0; }
.achievement-title { font-weight: 500; }
.achievement-detail { color: #666; font-size: 0.9rem; margin-left: 1rem; }
.achievement-link { font-size: 0.85rem; margin-left: 1rem; }
.achievement-link a { color: var(--primary); }

.highlight-metric {
  color: var(--primary);
  font-weight: 600;
}

.skills-grid {
  display: grid;
  grid-template-columns: 100px 1fr;
  gap: 0.5rem 1rem;
  margin: 1rem 0;
}
.skills-grid .label { font-weight: 500; color: #666; }

.activity-item { margin: 1rem 0; }
.activity-title { font-weight: 500; }
.activity-meta { color: #666; font-size: 0.9rem; }
.activity-desc { font-size: 0.95rem; margin-top: 0.25rem; }

/* Print 스타일 - PDF 변환 시 섹션별 페이지 분리 */
@media print {
  body {
    font-size: 11pt;
    line-height: 1.5;
  }
  .resume-header {
    background: #f5f5f5 !important;
    -webkit-print-color-adjust: exact;
    print-color-adjust: exact;
  }
  /* Experience 섹션 시작 시 새 페이지 */
  .page-break-experience { page-break-before: always; }
  /* 한화솔루션부터 새 페이지 (42dot 내용이 길어서) */
  .page-break-company { page-break-before: always; }
  /* Activity 섹션 시작 시 새 페이지 */
  .page-break-activity { page-break-before: always; }
  /* 프로젝트 중간에 페이지 분리 방지 */
  .project { page-break-inside: avoid; }
  .achievement { page-break-inside: avoid; }
  .activity-item { page-break-inside: avoid; }
  /* 링크 URL 숨김 (PDF에서 깔끔하게) */
  a[href]:after { content: none !important; }
}
</style>

<div class="resume-header">
  <img src="/dev-notes/images/profile.png" alt="김대겸" class="profile-img">
  <div class="resume-header-text">
    <h1>김대겸</h1>
    <div class="subtitle">Backend Engineer · 7년차</div>
    <div class="intro">
      대규모 데이터 파이프라인 설계와 안정적인 시스템 운영에 강점을 가진 백엔드 개발자.<br>
      50만대 장비의 실시간 데이터를 처리하는 시스템을 설계하고,<br>
      데이터 수집 성공률을 98%에서 100%로 개선한 경험이 있습니다.
    </div>
    <div class="contact-row">
      <span>📧 koreatech93@naver.com</span>
      <a href="https://github.com/gyeom">GitHub</a>
      <a href="https://medium.com/@rlaeorua369">Medium</a>
      <a href="https://gyeom.github.io/dev-notes/">Dev Notes</a>
    </div>
  </div>
</div>
{{< /rawhtml >}}

---

## Core Competencies {.section-title}

| 영역 | 역량 |
|:-----|:-----|
| **대용량 데이터** | 분당 50만 건 데이터 수집 파이프라인 설계 및 성능 최적화 |
| **메시징 시스템** | Kafka 기반 이벤트 파이프라인, DLT 재처리 전략, Outbox 패턴 |
| **아키텍처** | Hexagonal Architecture 기반 멀티모듈 설계 |
| **인가** | RBAC, ReBAC 기반 권한 관리 설계 |
| **테스팅** | Testcontainers 기반 통합 테스트 환경 구축, 커버리지 90% |

---

## Tech Stack {.section-title}

{{< rawhtml >}}
<div class="skills-grid">
  <span class="label">Backend</span>
  <span>Kotlin, Java, Spring Boot, JPA, QueryDSL</span>
  <span class="label">Data</span>
  <span>PostgreSQL, TimescaleDB, Redis, Kafka</span>
  <span class="label">Infra</span>
  <span>Docker, Kubernetes, AWS (S3, CloudFront)</span>
  <span class="label">DevOps</span>
  <span>GitLab CI, ArgoCD, Jenkins</span>
  <span class="label">Test</span>
  <span>Kotest, JUnit5, Testcontainers</span>
</div>
{{< /rawhtml >}}

---

## Experience {.section-title}

{{< rawhtml >}}
<div class="company-header">
  <h3>포티투닷 (42dot)</h3>
  <div class="company-meta">Backend Engineer · Vehicle Cloud · 2024.05 - 현재</div>
  <div class="company-desc">현대자동차 자율주행/SDV 차량 데이터 수집 및 라이프사이클 관리 시스템 설계/운영</div>
</div>

<div class="project">
  <div class="project-title">Vehicle Platform 서버 설계/운영</div>
  <div class="project-subtitle">분산된 차량/단말 관리 체계 통합 표준화, EU Data Act 법규 대응</div>

  <div class="achievement">
    <div class="achievement-title">▸ Transactional Outbox 패턴으로 이벤트 발행 신뢰성 확보</div>
    <div class="achievement-detail">
      DB 트랜잭션과 Kafka 메시지 발행 간 원자성 미보장 문제 해결<br>
      → Outbox 테이블 + @TransactionalEventListener 기반 하이브리드 패턴 구현
    </div>
    <div class="achievement-link">📝 <a href="/dev-notes/posts/2024-12-01-transactional-outbox-pattern-deep-dive/">블로그: Transactional Outbox 패턴</a></div>
  </div>

  <div class="achievement">
    <div class="achievement-title">▸ DLQ 기반 메시지 재처리로 데이터 정합성 확보</div>
    <div class="achievement-detail">
      특정 차량/단말 버전에서 발생하는 엣지 케이스 오류 미발견 문제<br>
      → PostgreSQL 기반 DLQ + 재처리 메커니즘 구현<br>
      → 데이터 유실 제로 달성
    </div>
    <div class="achievement-link">📝 <a href="/dev-notes/posts/2025-12-05-dlq-retry-strategy-kafka-postgresql/">블로그: DLQ 재처리 전략</a></div>
  </div>

  <div class="achievement">
    <div class="achievement-title">▸ 테스트 환경 구축 및 커버리지 <span class="highlight-metric">90%</span> 달성</div>
    <div class="achievement-detail">
      프로덕션과 동일한 환경에서 신뢰할 수 있는 테스트 체계 구축<br>
      → Source Set 분리로 단위/통합 테스트 명확히 구분<br>
      → Testcontainers 기반 실제 DB·캐시·메시징 환경 테스트<br>
      → 테스트 간 데이터 격리로 실행 순서 무관하게 안정적 실행<br>
      → Mock은 외부 API 연동에만 제한적 사용
    </div>
    <div class="achievement-link">📝 <a href="/dev-notes/posts/2025-12-05-testcontainers-integration-test-strategy/">블로그: Testcontainers 기반 통합 테스트 전략</a></div>
  </div>

  <div class="achievement">
    <div class="achievement-title">▸ ReBAC 기반 권한 관리 설계</div>
    <div class="achievement-detail">
      차량 10,000대 × 사용자 500명 = 개별 권한 부여 시 튜플 폭발 문제<br>
      → OpenFGA 기반 ReBAC + Group 패턴으로 <span class="highlight-metric">5,000,000개 → 수천 개</span> 튜플 축소
    </div>
    <div class="achievement-link">📝 <a href="/dev-notes/posts/2025-12-03-rebac-group-pattern-real-world/">블로그: ReBAC Group 패턴 실전 적용기</a></div>
  </div>

  <div class="achievement">
    <div class="achievement-title">▸ Observability 체계 구축</div>
    <div class="achievement-detail">
      LGTM 스택(Loki, Grafana, Tempo, Mimir) 기반 모니터링 환경 구성<br>
      → Micrometer + AOP 기반 커스텀 비즈니스 메트릭 설계<br>
      → Grafana Alert 설정으로 임계치 초과 시 Slack 알림 자동화<br>
      → 장애 감지 시간 단축 및 운영 가시성 확보
    </div>
  </div>

  <div class="achievement">
    <div class="achievement-title">▸ API Gateway Rate Limiting 구현</div>
    <div class="achievement-detail">
      서비스 안정성 확보를 위한 Rate Limiting 설계<br>
      → Token Bucket 알고리즘 + Redis 기반 분산 환경 구현
    </div>
    <div class="achievement-link">📝 <a href="/dev-notes/posts/2024-12-01-rate-limiting-deep-dive/">블로그: Rate Limiting 완벽 가이드</a></div>
  </div>

  <div class="achievement">
    <div class="achievement-title">▸ 기타 성과</div>
    <div class="achievement-detail">
      • Hexagonal Architecture 기반 서비스 설계로 외부 의존성 격리<br>
      • Kotlin JPA 엔티티 설계 (Persistable 인터페이스 활용)
        <a href="https://medium.com/@rlaeorua369/kotlin-%EA%B8%B0%EB%B0%98-jpa-%EC%97%94%ED%8B%B0%ED%8B%B0-%EC%84%A4%EA%B3%84-%EC%A0%84%EB%9E%B5-28ccc31d0c2b">📝</a><br>
      • Kafka DLT/DLQ + Idempotency 설계로 데이터 정합성 보장<br>
      • OpenAPI 3.0 + AsyncAPI 기반 API 문서 표준화<br>
      • QueryDSL → OpenFeign QueryDSL 마이그레이션 (CVE 대응)
        <a href="https://medium.com/@rlaeorua369/openfeign-querydsl-%EB%A7%88%EC%9D%B4%EA%B7%B8%EB%A0%88%EC%9D%B4%EC%85%98-%EC%B4%9D%EC%A0%95%EB%A6%AC-dee89cb3ec05">📝</a>
    </div>
  </div>
</div>

{{< /rawhtml >}}

{{< rawhtml >}}
<div class="company-header page-break-company">
  <h3>한화솔루션</h3>
  <div class="company-meta">Backend Engineer · 소프트웨어 개발팀 · 2021.05 - 2024.04</div>
  <div class="company-desc">홈 에너지 관리 시스템(HEMS) 개발<br>태양광·EV 충전기·스마트 가전 데이터 수집 및 최적화 (OCPP, SmartThings 등 연동)</div>
</div>

<div class="project">
  <div class="project-title">Telemetry 서비스 설계 및 대용량 아키텍처 구축</div>
  <div class="project-subtitle">레거시 데이터 수집 구조를 대체하는 신규 서비스 설계</div>

  <div class="achievement">
    <div class="achievement-title">▸ <span class="highlight-metric">분당 50만 건</span> 데이터 처리 아키텍처 구축</div>
    <div class="achievement-detail">
      기존 시스템(수만 대 수준) → 50만대 장비 수용 필요<br>
      → Batch Consumer + Spring JDBC Bulk Insert + @Async Thread Pool 튜닝<br>
      → 시뮬레이터 기반 부하테스트로 안정성 검증
    </div>
    <div class="achievement-link">📝 <a href="/dev-notes/posts/2023-12-08-kafka-high-volume-processing/">블로그: Kafka 대용량 메시지 처리</a></div>
  </div>

  <div class="achievement">
    <div class="achievement-title">▸ 데이터 수집 성공률 <span class="highlight-metric">98% → 100%</span> 개선</div>
    <div class="achievement-detail">
      특정 펌웨어 버전에서 발생하는 엣지 케이스 오류 미발견 문제<br>
      → Kafka DLT 기반 재처리 메커니즘 + 모니터링 체계 강화<br>
      → 기존에 발견하지 못한 수십 개 엣지 케이스 오류 해결
    </div>
    <div class="achievement-link">📝 <a href="/dev-notes/posts/2023-12-11-kafka-dlt-strategy/">블로그: Kafka DLT 재처리 전략</a></div>
  </div>

  <div class="achievement">
    <div class="achievement-title">▸ 글로벌 서비스 API 설계</div>
    <div class="achievement-detail">
      Timezone/DST 고려한 API 설계 (미국, 유럽, 호주)<br>
      Spring Rest Docs + Swagger UI 기반 <span class="highlight-metric">300여 개</span> E2E 테스트 작성
    </div>
    <div class="achievement-link">🎤 <a href="https://springcamp.ksug.org/2023/">Spring Camp 2023 발표: 글로벌 서비스를 위한 Timezone/DST</a></div>
  </div>

  <div class="achievement">
    <div class="achievement-title">▸ API 조회 성능 최적화</div>
    <div class="achievement-detail">
      Redis 캐싱 도입으로 API 응답 시간 개선<br>
      → Cache-Aside 패턴 + 이벤트 기반 캐시 무효화 적용<br>
      → 캐시 Hit Rate <span class="highlight-metric">90%</span> 이상 달성
    </div>
    <div class="achievement-link">📝 <a href="/dev-notes/posts/2025-12-05-redis-caching-strategy-real-world/">블로그: Redis 캐싱 전략</a></div>
  </div>
</div>
{{< /rawhtml >}}

{{< rawhtml >}}
<div class="company-header">
  <h3>롯데정보통신</h3>
  <div class="company-meta">Android Developer · 2019.07 - 2021.05</div>
  <div class="company-desc">롯데홈쇼핑 라이브 커머스 플랫폼 WYD 앱 개발</div>
</div>

<div class="project">
  <div class="project-title">WYD Android 앱 개발 및 운영</div>
  <div class="project-subtitle">실시간 라이브 방송 + 채팅 + 상품 구매 통합 플랫폼</div>

  <div class="achievement">
    <div class="achievement-detail">
      • <span class="highlight-metric">누적 50만 다운로드</span> Android 앱 개발 (Native 영역 기여도 80%)<br>
      • Crashlytics 모니터링으로 <span class="highlight-metric">앱 안정성 99%+</span> 유지 (크래시율 1% 미만)<br>
      • Multi Module 기반 프로젝트 구조 설계<br>
      • GA, Adbrix 연동으로 데이터 기반 마케팅 지원
    </div>
  </div>
</div>
{{< /rawhtml >}}

---

## Activity {.section-title}

{{< rawhtml >}}
<div class="activity-item">
  <div class="activity-title">🔧 OpenFeign QueryDSL 오픈소스 기여</div>
  <div class="activity-meta">2025.05</div>
  <div class="activity-desc">
    @JdbcTypeCode 적용 필드를 KSP 코드 생성에서 인식하지 못하는 문제 수정
    → <a href="https://github.com/OpenFeign/querydsl/pull/1127">PR #1127</a>
  </div>
</div>

<div class="activity-item">
  <div class="activity-title">🛠 Gradle/Maven Dependency Explorer</div>
  <div class="activity-meta">IntelliJ Plugin · 2024.12 ~</div>
  <div class="activity-desc">
    의존성 패턴을 분석하여 Maven Repository에서 라이브러리 정보를 바로 확인할 수 있는 플러그인<br>
    → <a href="https://plugins.jetbrains.com/plugin/25968-gradle-maven-dependency-explorer">JetBrains Marketplace</a>
    · <a href="https://medium.com/@rlaeorua369/intellij-%ED%94%8C%EB%9F%AC%EA%B7%B8%EC%9D%B8-%EA%B0%9C%EB%B0%9C%EA%B8%B0-gradle-maven-dependency-explorer-%EB%A7%8C%EB%93%A4%EA%B8%B0-5a3ffbb6da7a">개발기</a>
  </div>
</div>

<div class="activity-item">
  <div class="activity-title">🎤 Spring Camp 2023 연사 발표</div>
  <div class="activity-meta">2023.04</div>
  <div class="activity-desc">
    "글로벌 서비스를 위한 Timezone/DST" 주제로 발표
    → <a href="https://springcamp.ksug.org/2023/">Spring Camp 2023</a>
  </div>
</div>

<div class="activity-item">
  <div class="activity-title">📚 우아한테크캠프 Pro 5기</div>
  <div class="activity-meta">2022.10 - 2022.12</div>
  <div class="activity-desc">
    온라인 미션 기반 코드 리뷰 과정 <strong>우수 수료</strong>
  </div>
</div>
{{< /rawhtml >}}

---

## Education {.section-title}

**한국기술교육대학교** · 정보통신공학과 · 2012.03 - 2019.08
