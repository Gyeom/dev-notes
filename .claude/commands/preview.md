---
description: 로컬에서 블로그를 미리보기한다
allowed-tools:
  - Bash
---

Hugo 개발 서버를 실행하여 블로그를 미리본다.

## 실행

**공개 블로그 (dev-notes):**
```bash
hugo server -D
```

**비공개 블로그 (dev-notes-private):**
```bash
cd temp && hugo server -D -p 1314
```

**둘 다 동시에:**
```bash
hugo server -D & (cd temp && hugo server -D -p 1314)
```

## 안내

- 공개: http://localhost:1313/dev-notes/
- 비공개: http://localhost:1314/
- 종료: Ctrl+C (또는 `pkill -f "hugo server"`)
- `-D` 옵션: draft 포스트도 표시
