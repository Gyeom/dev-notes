---
description: 포스트를 백업한다
allowed-tools:
  - Read
  - Bash
  - Glob
argument-hint: [all|검색어]
---

포스트를 백업 파일로 저장한다.

## 실행

1. 인자에 따라 백업 대상 결정
   - `all`: 모든 포스트 백업
   - 검색어: 특정 포스트만 백업
   - 없음: 모든 포스트 백업
2. `backups/YYYY-MM-DD/` 디렉토리 생성
3. 포스트 파일 복사
4. 백업 완료 메시지 출력

## 인자

- $1: `all` 또는 검색어 (선택)

## 백업 위치

```
backups/
└── 2025-11-29/
    ├── posts/
    │   ├── 2025-11-29-post1.md
    │   └── 2025-11-29-post2.md
    └── backup-info.txt
```

## 주의사항

- backups/ 디렉토리는 .gitignore에 추가되어 있어야 함
- 동일 날짜 백업은 덮어쓰기
