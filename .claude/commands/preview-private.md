---
description: Private 블로그(temp/)를 로컬에서 미리보기한다
allowed-tools:
  - Bash
---

temp 폴더의 Hugo 개발 서버를 실행한다.

## 실행

```bash
cd /Users/a13801/dev-notes/temp && hugo server -D -p 1314
```

## 안내

- URL: http://localhost:1314/
- 종료: Ctrl+C (또는 `pkill -f "hugo server"`)
- `-D` 옵션: draft 포스트도 표시
