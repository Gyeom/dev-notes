---
description: 포스트를 proofreader와 seo-optimizer로 검토한다
allowed-tools:
  - Read
  - Glob
argument-hint: <검색어 또는 파일명>
---

포스트를 글쓰기 가이드와 SEO 관점에서 검토한다.

## 실행

1. 검색어로 포스트 찾기
2. proofreader 에이전트로 문체 검토
3. seo-optimizer 에이전트로 SEO 검토
4. 종합 결과 및 수정 제안

## 인자

- $1: 검색어 (제목 일부 또는 파일명)

검색어가 없으면 가장 최근 포스트를 검토한다.
