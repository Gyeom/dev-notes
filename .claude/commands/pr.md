---
description: 변경사항을 PR로 생성한다
allowed-tools:
  - Bash
  - Read
  - Glob
argument-hint: [브랜치명]
---

현재 변경사항으로 Pull Request를 생성한다.

## 순서

1. `git status`로 변경사항 확인
2. 변경사항이 없으면 안내 후 종료
3. `hugo --gc --minify`로 빌드 테스트
4. 빌드 성공 시:
   - 브랜치 생성 (인자가 없으면 `post/YYYY-MM-DD-제목` 형식)
   - 변경사항 커밋
   - 브랜치 푸시
   - `gh pr create`로 PR 생성
5. PR URL 안내

## 브랜치명 규칙

- 인자로 브랜치명을 받으면 그대로 사용
- 인자가 없으면:
  - 포스트 추가: `post/YYYY-MM-DD-슬러그`
  - 포스트 수정: `update/YYYY-MM-DD-슬러그`
  - 설정 변경: `chore/간단한-설명`

## PR 템플릿

```markdown
## Summary
- 변경 내용 요약 (1-3줄)

## Changes
- 변경된 파일 목록

## Preview
배포 후 확인: https://gyeom.github.io/dev-notes/

---
🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

## 사용 예시

```bash
/pr                      # 자동 브랜치명
/pr feature/new-section  # 직접 브랜치명 지정
```

## 후속 작업 안내

PR 생성 후 다음 안내를 포함한다:
- PR에서 `@claude 보완해줘` 등으로 추가 수정 요청 가능
- 확인 후 merge하면 자동 배포됨
