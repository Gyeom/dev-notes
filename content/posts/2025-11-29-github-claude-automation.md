---
title: "GitHub 이슈에서 @claude 멘션으로 자동 PR 생성하기"
date: 2025-11-29
draft: false
tags: ["GitHub Actions", "Claude Code", "자동화", "CI/CD", "AI"]
categories: ["개발환경"]
summary: "GitHub 이슈에서 @claude를 멘션하면 Claude가 코드를 작성하고 PR까지 자동 생성하는 워크플로우 구축 과정을 정리했다."
---

GitHub 이슈에서 `@claude`를 멘션하면 Claude가 요청을 처리하고, 파일을 생성하고, PR까지 자동으로 올리는 워크플로우를 구축했다. 이 글에서는 전체 과정을 단계별로 정리한다.

## 완성된 워크플로우

![GitHub Actions 실행 목록](/dev-notes/images/github-claude-automation/05-actions-list.png)

최종 흐름은 다음과 같다.

```
이슈에 @claude 멘션
    ↓
GitHub Actions 트리거
    ↓
Claude Code 실행 (파일 생성)
    ↓
브랜치 생성 + 커밋
    ↓
PR 자동 생성
    ↓
리뷰 후 머지
```

---

## 1. 사전 준비

### Anthropic API 키 등록

GitHub 저장소 Settings > Secrets and variables > Actions에서 `ANTHROPIC_API_KEY`를 등록한다.

```bash
gh secret set ANTHROPIC_API_KEY --repo username/repo-name
```

### Actions 권한 설정

PR 생성을 위해 Actions가 쓰기 권한을 가져야 한다.

```bash
gh api repos/username/repo-name/actions/permissions/workflow \
  -X PUT \
  -f default_workflow_permissions="write" \
  -F can_approve_pull_request_reviews=true
```

---

## 2. 워크플로우 파일 작성

`.github/workflows/claude.yml`:

```yaml
name: Claude AI Assistant

on:
  issue_comment:
    types: [created]
  pull_request_review_comment:
    types: [created]
  issues:
    types: [opened, assigned]

jobs:
  claude-response:
    if: contains(github.event.comment.body, '@claude') || contains(github.event.issue.body, '@claude')
    runs-on: ubuntu-latest

    permissions:
      contents: write
      issues: write
      pull-requests: write

    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Setup Git
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '20'

      - name: Install Claude Code
        run: npm install -g @anthropic-ai/claude-code

      - name: Run Claude
        env:
          ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          ISSUE_NUMBER: ${{ github.event.issue.number }}
        run: |
          COMMENT_BODY="${{ github.event.comment.body || github.event.issue.body }}"
          PROMPT=$(echo "$COMMENT_BODY" | sed 's/.*@claude//')

          RESPONSE=$(claude -p "$PROMPT" --max-turns 20 2>&1) || true

          if [ -n "$(git status --porcelain)" ]; then
            BRANCH_NAME="claude/issue-${ISSUE_NUMBER}-$(date +%Y%m%d%H%M%S)"
            git checkout -b "$BRANCH_NAME"

            git add .
            git commit -m "feat: Claude가 이슈 #${ISSUE_NUMBER} 요청 처리"
            git push -u origin "$BRANCH_NAME"

            PR_URL=$(gh pr create \
              --title "Claude: 이슈 #${ISSUE_NUMBER} 요청 처리" \
              --body "Closes #${ISSUE_NUMBER}" \
              --base main \
              --head "$BRANCH_NAME")

            RESULT_MSG="PR 생성됨: $PR_URL"
          else
            RESULT_MSG="파일 변경사항 없음"
          fi

          gh issue comment ${ISSUE_NUMBER} --body "## Claude 응답

          $RESPONSE

          ---
          $RESULT_MSG"
```

### 핵심 포인트

| 항목 | 설명 |
|------|------|
| `GITHUB_TOKEN` | GitHub이 자동 제공, 별도 설정 불필요 |
| `permissions` | contents, issues, pull-requests 쓰기 권한 |
| `--max-turns 20` | 복잡한 작업을 위해 충분한 턴 수 확보 |
| 브랜치 명명 | `claude/issue-{번호}-{타임스탬프}` 형식 |

---

## 3. 실제 사용 예시

### 이슈 생성

![이슈 목록](/dev-notes/images/github-claude-automation/01-issues-list.png)

이슈를 생성하고 본문에 `@claude`를 멘션한다.

```
@claude Kotlin Coroutines 기초 가이드 포스트를 content/posts/ 폴더에 작성해줘.
```

### Claude 응답 및 PR 생성

![이슈 상세](/dev-notes/images/github-claude-automation/02-issue-detail.png)

Claude가 파일을 생성하고 PR을 만든다.

![PR 목록](/dev-notes/images/github-claude-automation/03-pr-list.png)

### PR 상세

![PR 상세](/dev-notes/images/github-claude-automation/04-pr-detail.png)

PR에는 관련 이슈 링크(`Closes #3`)가 포함되어, 머지 시 이슈가 자동으로 닫힌다.

### 워크플로우 실행 로그

![워크플로우 실행](/dev-notes/images/github-claude-automation/06-workflow-run.png)

Actions 탭에서 실행 로그를 확인할 수 있다.

---

## 4. GITHUB_TOKEN 동작 원리

별도 토큰 설정 없이 `${{ secrets.GITHUB_TOKEN }}`을 사용할 수 있는 이유가 궁금할 수 있다.

### 자동 생성 메커니즘

1. 워크플로우 실행 시 GitHub이 임시 토큰 발급
2. 해당 저장소에 대한 권한만 부여
3. 워크플로우 종료 시 토큰 자동 폐기

### PAT vs GITHUB_TOKEN

| 구분 | GITHUB_TOKEN | PAT |
|------|--------------|-----|
| 범위 | 해당 저장소만 | 여러 저장소 |
| 수명 | 워크플로우 실행 중만 | 수동 관리 |
| 설정 | 자동 | 수동 등록 필요 |

---

## 5. 활용 사례

### 포스트 작성 요청

```
@claude Docker Compose 로컬 개발 환경 구성 가이드 포스트를 작성해줘.
Spring Boot + PostgreSQL + Redis 조합으로.
```

### 버그 수정 요청

```
@claude 이 파일의 타입 에러 수정해줘.
src/utils/date.ts
```

### 문서 개선 요청

```
@claude README에 설치 방법과 사용법 섹션 추가해줘.
```

---

## 6. 주의사항

### max-turns 설정

복잡한 작업은 기본 턴 수로 부족할 수 있다. `--max-turns 20` 이상 권장.

### Actions 권한

PR 생성 시 `GitHub Actions is not permitted to create pull requests` 에러가 발생하면 저장소 설정에서 권한을 추가해야 한다.

### 비용

Claude API 호출 비용이 발생한다. 복잡한 요청일수록 토큰 사용량이 증가한다.

---

## 결과

![블로그 메인](/dev-notes/images/github-claude-automation/07-blog-main.png)

GitHub 이슈에서 `@claude`를 멘션하는 것만으로 코드 생성부터 PR까지 자동화됐다. 리뷰 후 머지하면 배포까지 완료된다.

**장점**
- 반복적인 작업 자동화
- 코드 리뷰 프로세스 유지
- 이슈 트래킹과 자연스럽게 연동

**확장 가능성**
- PR 코멘트에서도 `@claude` 멘션으로 코드 수정 요청
- 라벨 기반 자동 할당
- 특정 조건에서만 Claude 실행

이 워크플로우를 기반으로 다양한 자동화를 구축할 수 있다.
