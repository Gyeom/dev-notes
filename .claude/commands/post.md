---
description: 새 블로그 포스트를 작성하고 배포한다
allowed-tools:
  - Read
  - Write
  - Bash
  - Glob
argument-hint: <제목> [태그들]
---

사용자가 요청한 내용을 블로그 포스트로 작성한다.

## 규칙

1. `.claude/writing-guide.md`의 글쓰기 규칙을 따른다
2. 파일명: `content/posts/YYYY-MM-DD-slug.md` 형식
3. Front matter 필수: title, date, draft, tags, summary

## 작성 후

1. `hugo --gc --minify`로 빌드 테스트
2. 사용자에게 미리보기 제안 또는 바로 배포 여부 확인
3. 배포 시: `git add . && git commit -m "Add: 포스트제목" && git push`

## 인자

- $1: 포스트 제목
- $2: 태그 (쉼표 구분, 선택)

제목이 없으면 사용자에게 물어본다.
