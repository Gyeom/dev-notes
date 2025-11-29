---
description: 최근 포스트 목록을 보여준다
allowed-tools:
  - Bash
  - Read
  - Glob
argument-hint: [개수]
---

블로그의 최근 포스트 목록을 보여준다.

## 실행

1. `content/posts/` 디렉토리에서 최근 파일 조회
2. 각 파일의 제목, 날짜, 태그, draft 상태 표시
3. 기본 10개, 인자로 개수 지정 가능

## 출력 형식

```
[날짜] 제목 (태그1, 태그2) [draft]
```

## 인자

- $1: 표시할 포스트 개수 (기본: 10)
