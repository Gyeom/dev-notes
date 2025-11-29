---
description: 포스트를 proofreader와 seo-optimizer로 검토한다
allowed-tools:
  - Read
  - Glob
  - Task
argument-hint: <검색어 또는 파일명>
---

포스트를 글쓰기 가이드와 SEO 관점에서 검토한다.

## 실행

1. 검색어로 포스트 찾기
2. **Subagent 병렬 실행**:
   - Task tool로 proofreader 에이전트 실행 (문체 검토)
   - Task tool로 seo-optimizer 에이전트 실행 (SEO 검토)
   - 두 에이전트를 **동시에** 호출하여 성능 최적화
3. 각 에이전트 결과 종합
4. 최종 수정 제안

## Subagent 패턴

각 에이전트는 독립된 컨텍스트에서 실행된다. 이렇게 하면:
- 메인 컨텍스트가 오염되지 않음
- 병렬 실행으로 시간 단축
- 각 에이전트가 전문 영역에 집중

## 인자

- $1: 검색어 (제목 일부 또는 파일명)

검색어가 없으면 가장 최근 포스트를 검토한다.
