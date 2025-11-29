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

1. 검색어로 포스트 찾기 (Glob 사용)
2. 포스트 내용 읽기 (Read 사용)
3. **Subagent 병렬 실행**: 반드시 하나의 메시지에서 두 Task를 동시에 호출한다.
   - Task 1: `subagent_type=proofreader` → 문체 검토
   - Task 2: `subagent_type=seo-optimizer` → SEO 검토
4. 두 결과 종합하여 표로 정리
5. 수정 적용 여부 질문

## 병렬 실행 방법

**중요**: 30-40% 비용/시간 절감을 위해 두 Task tool을 **같은 응답**에서 호출해야 한다.

proofreader와 seo-optimizer Task를 동시에 호출하면 병렬로 실행된다. 순차 호출 시 직렬 실행되어 시간이 2배 소요된다.

## 결과 정리 형식

| 구분 | 항목 | 상태 | 제안 |
|------|------|------|------|
| 문체 | ~다체 사용 | ✅/❌ | 수정 내용 |
| 문체 | 피해야 할 표현 | ✅/❌ | 수정 내용 |
| SEO | 제목 최적화 | ✅/❌ | 제안 |
| SEO | 요약문 길이 | ✅/❌ | 제안 |
| SEO | 태그 적절성 | ✅/❌ | 제안 |

## 참고

- 글쓰기 가이드: @.claude/writing-guide.md
- "~할 수 있다"는 **가능성/능력** 표현 시 사용 가능
