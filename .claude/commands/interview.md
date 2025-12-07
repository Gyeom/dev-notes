# 면접 자료 조회

면접 준비 자료를 조회한다.

## 사용법

- `/interview` - 전체 목차
- `/interview kafka` - Kafka 관련 자료
- `/interview 아키텍처` - 아키텍처 관련 자료
- `/interview open` - 브라우저에서 목차 열기
- `/interview open kafka` - 브라우저에서 Kafka 자료 열기

## 인자: $ARGUMENTS

## 실행

### 브라우저로 열기 (open 인자)
인자가 `open`으로 시작하면 IDE나 브라우저에서 해당 파일을 연다.
- `/interview open` → `.claude/knowledge/interview/00-index.md` 파일을 IDE에서 열기
- `/interview open kafka` → 관련 파일들을 IDE에서 열기

### CLI에서 조회
1. 인자가 없으면 `.claude/knowledge/interview/00-index.md` 목차를 보여준다.

2. 인자가 있으면 해당 키워드로 `.claude/knowledge/interview/` 폴더에서 관련 문서를 찾아 내용을 보여준다.
   - 키워드 매핑:
     - kafka, 카프카 → 02-kafka-batch-processing.md, 03-kafka-dlt-dlq.md
     - outbox → 04-outbox-pattern.md
     - test, 테스트 → 05-testcontainers.md, 06-testing-strategy.md
     - openfga, rebac, 권한 → 07-openfga-rebac.md
     - rate, 레이트 → 08-rate-limiting.md
     - redis, 캐시 → 09-redis-caching.md
     - postgres, pg, 디비 → 10-postgresql.md
     - timescale → 11-timescaledb.md
     - hexagonal, 헥사고날, 아키텍처 → 12-hexagonal.md
     - module, 모듈 → 13-multi-module.md
     - kotlin, jpa → 14-kotlin-jpa.md
     - spring → 15-spring-core.md
     - observability, 모니터링 → 16-observability.md
     - 문제, problem → 17-problem-solving.md
     - 협업, team → 18-collaboration.md
     - 성장, growth → 19-growth.md
     - 소개, intro → 01-introduction.md

3. 문서 내용을 마크다운으로 정리해서 보여준다.
