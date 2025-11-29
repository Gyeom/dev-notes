---
description: 기존 포스트를 수정한다
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
argument-hint: <검색어 또는 파일명>
---

기존 포스트를 찾아서 수정한다.

## 실행

1. 검색어로 포스트 찾기 (제목 또는 파일명)
2. 여러 개 매칭되면 목록 보여주고 선택 요청
3. 수정 내용 확인 후 적용
4. `.claude/writing-guide.md` 규칙 준수

## 인자

- $1: 검색어 (제목 일부 또는 파일명)

검색어가 없으면 최근 포스트 목록을 보여주고 선택하게 한다.
