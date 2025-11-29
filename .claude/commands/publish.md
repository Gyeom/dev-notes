---
description: 초안 포스트를 발행한다 (draft: false)
allowed-tools:
  - Read
  - Edit
  - Bash
  - Glob
argument-hint: <검색어 또는 파일명>
---

draft 상태인 포스트를 발행 상태로 변경한다.

## 실행

1. 검색어로 draft 포스트 찾기
2. `draft: true` → `draft: false` 변경
3. 빌드 테스트 후 배포 여부 확인

## 인자

- $1: 검색어 (제목 일부 또는 파일명)

검색어가 없으면 draft 포스트 목록을 보여준다.
