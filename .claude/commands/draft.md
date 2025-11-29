---
description: 초안 포스트를 작성한다 (draft: true)
allowed-tools:
  - Read
  - Write
  - Bash
  - Glob
argument-hint: <제목> [태그들]
---

초안 상태의 포스트를 작성한다. 나중에 /publish로 발행할 수 있다.

## 규칙

1. `.claude/writing-guide.md`의 글쓰기 규칙을 따른다
2. 파일명: `content/posts/YYYY-MM-DD-slug.md` 형식
3. Front matter에서 `draft: true` 설정
4. 로컬에서 `hugo server -D`로 확인 가능

## 인자

- $1: 포스트 제목
- $2: 태그 (쉼표 구분, 선택)

제목이 없으면 사용자에게 물어본다.
