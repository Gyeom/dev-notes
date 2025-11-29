---
title: "Claude Code Best Practice 프로젝트 구축기"
date: 2024-11-29
draft: false
tags: ["Claude Code", "Hugo", "GitHub Pages", "MCP", "자동화", "블로그"]
categories: ["개발환경"]
summary: "Hugo 블로그에 Claude Code의 모든 기능을 적용한 Best Practice 프로젝트 구축 과정을 정리했다."
---

## 개요

Claude Code로 개발 블로그를 만들면서, 2025년 기준 Claude Code의 모든 기능을 적용해봤다. 단순히 블로그를 만드는 것이 아니라 Claude Code Best Practice 프로젝트로 구성했다.

**적용한 기능**
- Hugo + GitHub Pages 자동 배포
- CLAUDE.md 프로젝트 메모리
- 커스텀 슬래시 명령어 9개
- Skills (자동 호출) 2개
- Agents (명시적 호출) 2개
- Hooks (자동화)
- MCP 서버 (fetch, github)
- GitHub App (@claude 멘션)

---

## 1. Hugo + GitHub Pages 블로그 구축

### 프로젝트 생성

```bash
brew install hugo
hugo new site dev-notes --format toml
cd dev-notes
git init && git branch -m main
```

### PaperMod 테마 설치

```bash
git submodule add --depth=1 https://github.com/adityatelange/hugo-PaperMod.git themes/PaperMod
```

### hugo.toml 설정

```toml
baseURL = 'https://username.github.io/dev-notes/'
languageCode = 'ko-kr'
title = 'Dev Notes'
theme = 'PaperMod'

[pagination]
  pagerSize = 10

[params]
  defaultTheme = "auto"

  [params.homeInfoParams]
    Title = "Dev Notes"
    Content = "개발하면서 배운 것들을 기록합니다."

[menu]
  [[menu.main]]
    name = "Posts"
    url = "/posts/"
    weight = 10
  [[menu.main]]
    name = "Tags"
    url = "/tags/"
    weight = 20
  [[menu.main]]
    name = "Search"
    url = "/search/"
    weight = 30

[outputs]
  home = ["HTML", "RSS", "JSON"]

[markup.highlight]
  codeFences = true
  style = "monokai"
```

### GitHub Actions 자동 배포

`.github/workflows/deploy.yml`:

```yaml
name: Deploy Hugo site to GitHub Pages

on:
  push:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read
  pages: write
  id-token: write

jobs:
  build:
    runs-on: ubuntu-latest
    env:
      HUGO_VERSION: 0.152.2
    steps:
      - name: Install Hugo CLI
        run: |
          wget -O ${{ runner.temp }}/hugo.deb https://github.com/gohugoio/hugo/releases/download/v${HUGO_VERSION}/hugo_extended_${HUGO_VERSION}_linux-amd64.deb \
          && sudo dpkg -i ${{ runner.temp }}/hugo.deb

      - name: Checkout
        uses: actions/checkout@v4
        with:
          submodules: recursive

      - name: Setup Pages
        id: pages
        uses: actions/configure-pages@v5

      - name: Build with Hugo
        run: hugo --gc --minify --baseURL "${{ steps.pages.outputs.base_url }}/"

      - name: Upload artifact
        uses: actions/upload-pages-artifact@v3
        with:
          path: ./public

  deploy:
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    runs-on: ubuntu-latest
    needs: build
    steps:
      - name: Deploy to GitHub Pages
        uses: actions/deploy-pages@v4
```

### 저장소 생성 및 배포

```bash
gh auth login
gh repo create dev-notes --public --source=. --push
gh api repos/USERNAME/dev-notes/pages -X POST -f build_type=workflow
```

---

## 2. CLAUDE.md 프로젝트 메모리

Claude Code가 프로젝트를 이해하도록 `CLAUDE.md`를 작성했다.

```markdown
# Dev Notes

Hugo 기반 개발 블로그. 마크다운 작성 후 push하면 자동 배포된다.

## 빌드 및 배포

hugo --gc --minify        # 빌드
hugo server -D            # 로컬 미리보기
git push                  # 배포

## 슬래시 명령어

| 명령어 | 설명 |
|--------|------|
| /post | 새 포스트 작성 및 배포 |
| /draft | 초안 작성 |
| /list | 최근 포스트 목록 |
...

## 글쓰기 규칙

@.claude/writing-guide.md
```

`@` 문법으로 다른 파일을 참조할 수 있다.

---

## 3. 권한 설정 (.claude/settings.json)

```json
{
  "permissions": {
    "allow": [
      "Bash(hugo:*)",
      "Bash(git add:*)",
      "Bash(git commit:*)",
      "Bash(git push:*)",
      "Bash(./scripts/*)",
      "Read(content/**)",
      "Write(content/**)"
    ]
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash(git push:*)",
        "hooks": [
          {
            "type": "command",
            "command": "hugo --gc --minify > /dev/null 2>&1 || exit 2"
          }
        ]
      }
    ]
  }
}
```

- **permissions**: 자주 쓰는 명령어 자동 허용
- **hooks**: git push 전 빌드 테스트 자동 실행

---

## 4. 커스텀 슬래시 명령어

`.claude/commands/` 폴더에 마크다운 파일로 정의한다.

### /post 명령어

`.claude/commands/post.md`:

```markdown
---
description: 새 블로그 포스트를 작성하고 배포한다
allowed-tools:
  - Read
  - Write
  - Bash
argument-hint: <제목> [태그들]
---

사용자가 요청한 내용을 블로그 포스트로 작성한다.

## 규칙

1. .claude/writing-guide.md의 글쓰기 규칙을 따른다
2. 파일명: content/posts/YYYY-MM-DD-slug.md 형식
3. Front matter 필수: title, date, draft, tags, summary
```

### 전체 명령어 목록

| 명령어 | 설명 |
|--------|------|
| `/post` | 새 포스트 작성 및 배포 |
| `/draft` | 초안 작성 (draft: true) |
| `/publish` | 초안을 발행 |
| `/edit` | 기존 포스트 수정 |
| `/list` | 최근 포스트 목록 |
| `/stats` | 블로그 통계 |
| `/review` | 문체/SEO 검토 |
| `/deploy` | 변경사항 배포 |
| `/preview` | 로컬 미리보기 |

---

## 5. Skills vs Agents

### Skills (자동 호출)

Claude가 상황에 맞게 자동으로 사용한다.

`.claude/skills/auto-proofreader.md`:

```markdown
---
name: auto-proofreader
description: 포스트 작성 시 자동으로 기본 문체를 검사한다
allowed-tools:
  - Read
---

포스트 작성 완료 후 자동으로 검사한다.

## 검사 항목

- : 로 끝나는 문장 → 마침표로 수정
- ~입니다, ~합니다 → ~이다, ~한다로 수정
```

### Agents (명시적 호출)

상세 분석이 필요할 때 직접 호출한다.

```
proofreader 에이전트로 이 포스트 검토해줘
seo-optimizer로 SEO 분석해줘
```

### 역할 분담

| 유형 | 용도 | 예시 |
|------|------|------|
| Skill | 자동 호출, 기본 검사 | auto-proofreader, auto-tagger |
| Agent | 명시적 호출, 심층 분석 | proofreader, seo-optimizer |

---

## 6. MCP 서버 연동

### 설치

```bash
# Fetch MCP - URL 내용 가져오기
claude mcp add fetch -- uvx mcp-server-fetch

# GitHub MCP - 저장소 관리
claude mcp add github -- npx -y @modelcontextprotocol/server-github
```

### .mcp.json (팀 공유용)

```json
{
  "mcpServers": {
    "fetch": {
      "command": "uvx",
      "args": ["mcp-server-fetch"]
    },
    "github": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": {
        "GITHUB_PERSONAL_ACCESS_TOKEN": "${GITHUB_TOKEN}"
      }
    }
  }
}
```

### 활용 예시

```bash
# Fetch MCP
"이 URL 내용 요약해서 TIL로 올려줘"
"Spring 공식 문서에서 이 부분 정리해줘"

# GitHub MCP
"dev-notes 저장소 최근 이슈 확인해줘"
"배포 실패한 Actions 로그 분석해줘"
```

---

## 7. GitHub App (@claude 멘션)

이슈나 PR에서 `@claude`를 멘션하면 Claude가 응답한다.

### 워크플로우 설정

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
    if: contains(github.event.comment.body, '@claude')
    runs-on: ubuntu-latest
    permissions:
      contents: write
      issues: write
      pull-requests: write

    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'

      - run: npm install -g @anthropic-ai/claude-code

      - name: Run Claude
        env:
          ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          PROMPT=$(echo "${{ github.event.comment.body }}" | sed 's/.*@claude//')
          RESPONSE=$(claude -p "$PROMPT" --max-turns 5)
          gh issue comment ${{ github.event.issue.number }} --body "$RESPONSE"
```

### API 키 설정

```bash
gh secret set ANTHROPIC_API_KEY --repo USERNAME/dev-notes
```

### 사용 예시

이슈에서:
```
@claude 이 버그 원인 분석해줘
@claude README 개선 제안해줘
```

---

## 최종 프로젝트 구조

```
dev-notes/
├── CLAUDE.md                    # 프로젝트 메모리
├── .mcp.json                    # MCP 서버 설정
├── .claude/
│   ├── settings.json            # 권한 + Hooks
│   ├── writing-guide.md         # 글쓰기 규칙
│   ├── commands/                # 슬래시 명령어 9개
│   │   ├── post.md
│   │   ├── draft.md
│   │   ├── publish.md
│   │   ├── edit.md
│   │   ├── list.md
│   │   ├── stats.md
│   │   ├── review.md
│   │   ├── deploy.md
│   │   └── preview.md
│   ├── skills/                  # 자동 호출 스킬
│   │   ├── auto-proofreader.md
│   │   └── auto-tagger.md
│   └── agents/                  # 명시적 호출 에이전트
│       ├── proofreader.md
│       └── seo-optimizer.md
├── .github/workflows/
│   ├── deploy.yml               # Hugo 자동 배포
│   └── claude.yml               # @claude 멘션 응답
├── content/posts/               # 블로그 포스트
├── scripts/                     # 자동화 스크립트
└── themes/PaperMod/             # Hugo 테마
```

---

## 적용된 기능 체크리스트

| 기능 | 상태 |
|------|------|
| Hugo + GitHub Pages | ✅ |
| CLAUDE.md (프로젝트 메모리) | ✅ |
| @ 문법 (파일 참조) | ✅ |
| settings.json (권한) | ✅ |
| Hooks (빌드 자동화) | ✅ |
| 슬래시 명령어 9개 | ✅ |
| Skills 2개 | ✅ |
| Agents 2개 | ✅ |
| MCP 서버 2개 | ✅ |
| GitHub App (@claude) | ✅ |

---

## 사용 예시

```bash
# 포스트 작성
"이 내용 정리해서 포스팅해줘"

# 명령어 사용
/post "제목" 태그1,태그2
/list
/stats
/review

# 에이전트 호출
"proofreader로 최근 포스트 검토해줘"

# MCP 활용
"이 URL 내용 요약해서 TIL로 올려줘"
"dev-notes 저장소 이슈 확인해줘"

# GitHub에서 (@claude 멘션)
@claude 이 버그 수정해줘
```

---

## 결론

단순 블로그가 아닌 Claude Code의 모든 기능을 활용하는 Best Practice 프로젝트가 완성됐다.

핵심은 역할 분담이다.
- **Skills**: 반복적인 작업 자동화
- **Agents**: 필요할 때 심층 분석
- **Hooks**: 실수 방지 (배포 전 빌드 테스트)
- **MCP**: 외부 서비스 연동

이 구조를 다른 프로젝트에도 적용할 수 있다.
