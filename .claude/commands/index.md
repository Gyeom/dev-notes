포스트 인덱스를 갱신한다. 모든 포스트의 메타데이터를 수집하여 `.claude/knowledge/post-index.md`에 저장한다.

## 실행 절차

1. `content/posts/` 디렉토리의 모든 `.md` 파일 스캔
2. 각 파일에서 front matter 추출 (title, date, tags, summary)
3. 테이블 형식으로 인덱스 생성
4. `.claude/knowledge/post-index.md`에 저장

## 인덱스 형식

```markdown
# 포스트 인덱스

> 자동 생성됨. 수동 편집 금지.
> 마지막 갱신: YYYY-MM-DD HH:MM

## 전체 포스트 (N개)

| 파일 | 제목 | 날짜 | 태그 |
|------|------|------|------|
| filename.md | 제목 | 2025-01-01 | tag1, tag2 |

## 태그별 분류

### Claude Code
- 파일1.md - 제목
- 파일2.md - 제목

### GitHub
- ...
```

## 활용

- 포스트 검색 시 인덱스 먼저 참조
- 관련 포스트 연결 시 태그 기반 탐색
- `/sync` 명령어에서 활용
