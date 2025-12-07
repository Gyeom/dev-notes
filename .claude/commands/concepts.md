# 개념 레퍼런스 조회

핵심 개념 레퍼런스를 조회한다.

## 사용법

- `/concepts` - 전체 목차
- `/concepts kafka` - Kafka 개념
- `/concepts db` - 데이터베이스 개념
- `/concepts open` - 브라우저에서 목차 열기 (GitHub)
- `/concepts open db` - 브라우저에서 DB 개념 열기

## 인자: $ARGUMENTS

## 실행

### 브라우저로 열기 (open 인자)
인자가 `open`으로 시작하면 GitHub에서 해당 파일을 브라우저로 연다.

**GitHub 베이스 URL**: `https://github.com/Gyeom/dev-notes/blob/main/.claude/knowledge/concepts/`

- `/concepts open` → `open "https://github.com/Gyeom/dev-notes/blob/main/.claude/knowledge/concepts/00-index.md"` 실행
- `/concepts open kafka` → `open "https://github.com/Gyeom/dev-notes/blob/main/.claude/knowledge/concepts/01-kafka.md"` 실행

### CLI에서 조회
1. 인자가 없으면 `.claude/knowledge/concepts/00-index.md` 목차를 보여준다.

2. 인자가 있으면 해당 키워드로 `.claude/knowledge/concepts/` 폴더에서 관련 문서를 찾아 내용을 보여준다.
   - 키워드 매핑:
     - kafka, 카프카 → 01-kafka.md
     - distributed, 분산, saga, circuit → 02-distributed-patterns.md
     - test, 테스트, tdd, mock → 03-testing.md
     - db, database, postgres, redis, mvcc, vacuum → 04-database.md
     - architecture, 아키텍처, ddd, hexagonal, cqrs → 05-architecture.md
     - spring, kotlin, jpa, batch, security → 06-spring-kotlin.md
     - infra, k8s, kubernetes, docker, ci, cd, 모니터링 → 07-infrastructure.md

3. 문서 내용을 마크다운으로 정리해서 보여준다. 문서가 길면 주요 섹션 목차와 함께 요약을 보여준다.
