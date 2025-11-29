---
title: "Claude Code 완벽 가이드 - 입문부터 고급 활용까지"
date: 2024-11-29
draft: false
tags: ["Claude Code", "AI", "개발도구", "자동화", "MCP", "가이드", "Hugo", "GitHub Pages"]
categories: ["개발환경"]
summary: "Claude Code의 모든 기능을 정리한 종합 가이드. 설치부터 실전 프로젝트 적용까지."
---

## 개요

Claude Code는 Anthropic의 공식 CLI 기반 AI 코딩 어시스턴트다. 터미널에서 직접 코드를 읽고, 수정하고, 명령어를 실행한다.

이 가이드에서는 기본 사용법부터 실전 프로젝트에 적용하는 방법까지 모두 다룬다. 마지막에는 Hugo 블로그에 모든 기능을 적용한 Best Practice 사례를 소개한다.

**이 가이드에서 다루는 내용**
- 기본 사용법과 단축키
- 프로젝트 설정 (CLAUDE.md, settings.json)
- 커스텀 슬래시 명령어
- Skills와 Agents
- Hooks로 자동화
- MCP 서버 연동
- GitHub 연동
- 실전 적용 사례

---

## Part 1: 기본 사용법

### 1. 설치 및 시작

```bash
# npm으로 설치
npm install -g @anthropic-ai/claude-code

# 또는 brew (macOS)
brew install claude-code
```

### 첫 실행

```bash
claude              # 대화형 모드
claude "할 일"      # 단일 작업 실행
claude -p "질문"    # 결과만 출력 (파이프용)
```

### 세션 관리

```bash
claude -c           # 최근 세션 이어서
claude -r <id>      # 특정 세션 복원
```

---

### 2. 필수 단축키

| 단축키 | 기능 |
|--------|------|
| `Tab` | Extended Thinking 토글 (심화 분석) |
| `Shift+Tab` | Plan 모드 토글 (읽기 전용 분석) |
| `Ctrl+C` | 현재 작업 취소 |
| `Ctrl+L` | 화면 초기화 |
| `Ctrl+R` | 이전 명령어 검색 |
| `Ctrl+B` | 백그라운드에서 명령 실행 |
| `Esc` 2회 | 코드 변경 되돌리기 (/rewind) |
| `#` | 메모리에 빠르게 추가 |
| `@` | 파일 경로 자동완성 |
| `!` | Bash 명령어 직접 실행 |

```bash
/vim    # Vim 키바인딩 활성화
```

---

### 3. 모델 선택

| 모델 | 용도 |
|------|------|
| `sonnet` | 일반 코딩 (기본값, 빠름) |
| `opus` | 복잡한 분석 (느리지만 강력) |
| `haiku` | 간단한 작업 (가장 빠름) |
| `opusplan` | Opus로 계획 → Sonnet으로 실행 |
| `sonnet[1m]` | 100만 토큰 컨텍스트 (대형 프로젝트) |

```bash
claude --model opus   # CLI 옵션
/model sonnet         # 세션 중 변경
```

복잡한 문제는 `Tab`을 눌러 Extended Thinking을 활성화한다.

---

## Part 2: 프로젝트 설정

### 4. CLAUDE.md - 프로젝트 메모리

프로젝트 루트에 `CLAUDE.md`를 만들면 Claude가 자동으로 읽는다.

```markdown
# My Project

## 빌드 명령어
- Build: `npm run build`
- Test: `npm test`
- Lint: `npm run lint`

## 코드 스타일
- TypeScript 사용
- 함수명은 camelCase
- 컴포넌트는 PascalCase

## 규칙
- console.log 대신 logger 사용
- any 타입 금지
```

### 파일 임포트

`@` 문법으로 다른 파일을 참조한다.

```markdown
## 글쓰기 규칙

@.claude/writing-guide.md
```

최대 5단계까지 재귀적으로 참조한다.

### 메모리 계층

1. `~/.claude/CLAUDE.md` - 전역 (모든 프로젝트)
2. `./CLAUDE.md` - 프로젝트 (팀 공유)
3. 세션 중 `#`으로 추가한 내용

---

### 5. 권한 설정

`.claude/settings.json`:

```json
{
  "permissions": {
    "allow": [
      "Bash(npm:*)",
      "Bash(docker-compose:*)",
      "Read(src/**)",
      "Write(src/**)"
    ],
    "deny": [
      "Bash(rm -rf:*)",
      "Read(**/.env)"
    ],
    "ask": [
      "Bash(git push:*)"
    ]
  }
}
```

### 권한 규칙 문법

```
Tool(action:pattern)

- Bash(npm:*)        # npm 관련 모든 명령어 허용
- Read(src/**)       # src 하위 모든 파일 읽기 허용
- Write(*.md)        # 마크다운 파일만 쓰기 허용
```

### 설정 파일 위치

| 파일 | 범위 |
|------|------|
| `~/.claude/settings.json` | 전역 |
| `.claude/settings.json` | 프로젝트 (Git 공유) |
| `.claude/settings.local.json` | 로컬 (Git 무시) |

---

### 6. 커스텀 슬래시 명령어

`.claude/commands/review.md`:

```markdown
---
description: 코드 리뷰를 수행한다
allowed-tools:
  - Read
  - Grep
argument-hint: <파일경로>
---

$ARGUMENTS 파일의 코드를 리뷰한다.

다음을 확인한다.
- 보안 취약점
- 성능 이슈
- 코드 스타일
```

```bash
/review src/auth.ts
```

### 인자 접근

- `$ARGUMENTS` - 전체 인자
- `$1`, `$2` - 위치별 인자

---

## Part 3: 자동화

### 7. Skills vs Agents

둘 다 특화된 기능을 정의하지만 호출 방식이 다르다.

| 유형 | 호출 방식 | 용도 |
|------|----------|------|
| **Skill** | 자동 (Claude가 판단) | 반복적인 기본 작업 |
| **Agent** | 명시적 (사용자가 호출) | 심층 분석 |

### Skill 예시

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

### Agent 예시

`.claude/agents/security-reviewer.md`:

```markdown
---
name: security-reviewer
description: 보안 취약점을 찾는다
allowed-tools:
  - Read
  - Grep
system-prompt: |
  당신은 보안 전문가입니다.
  OWASP Top 10을 기준으로 취약점을 찾습니다.
---

보안 관점에서 코드를 분석한다.
```

```bash
security-reviewer 에이전트로 src/auth/ 폴더 검토해줘
```

---

### 8. Hooks

특정 이벤트에서 자동으로 실행되는 스크립트다.

### 사용 가능한 이벤트

- `PreToolUse` - 도구 실행 전
- `PostToolUse` - 도구 실행 후
- `PermissionRequest` - 권한 요청 시
- `SessionStart` - 세션 시작
- `SessionEnd` - 세션 종료

### 설정 예시

`.claude/settings.json`:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matchers": ["Edit"],
        "type": "command",
        "command": "prettier --write $FILE_PATH"
      }
    ],
    "PreToolUse": [
      {
        "matchers": ["Bash(git push:*)"],
        "type": "command",
        "command": "npm test || exit 2"
      }
    ]
  }
}
```

### 반환값

- `0` - 성공
- `2` - 작업 차단
- 기타 - 경고 후 계속 진행

---

## Part 4: 외부 연동

### 9. MCP 서버

Model Context Protocol. 외부 도구와 데이터 소스를 Claude에 연결한다.

### 서버 추가

```bash
# Fetch - URL 내용 가져오기
claude mcp add fetch -- uvx mcp-server-fetch

# GitHub - 저장소 관리
claude mcp add github -- npx -y @modelcontextprotocol/server-github
```

### 관리 명령어

```bash
claude mcp list          # 설치된 서버 목록
claude mcp get <name>    # 상세 정보
claude mcp remove <name> # 제거
```

### 설정 파일 (.mcp.json)

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
"이 URL 내용 요약해서 정리해줘"
"dev-notes 저장소 이슈 확인해줘"
"배포 실패한 Actions 로그 분석해줘"
```

---

### 10. GitHub 연동

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
gh secret set ANTHROPIC_API_KEY --repo USERNAME/REPO
```

### 사용 예시

```
@claude 이 버그 수정해줘
@claude 코드 리뷰해줘
@claude README 개선 제안해줘
```

---

## Part 5: 실전 적용 - Hugo 블로그 Best Practice

모든 기능을 Hugo 블로그에 적용한 사례다.

### 프로젝트 구조

```
dev-notes/
├── CLAUDE.md                    # 프로젝트 메모리
├── .mcp.json                    # MCP 서버 설정
├── .claude/
│   ├── settings.json            # 권한 + Hooks
│   ├── writing-guide.md         # 글쓰기 규칙
│   ├── commands/                # 슬래시 명령어
│   │   ├── post.md
│   │   ├── draft.md
│   │   ├── publish.md
│   │   ├── edit.md
│   │   ├── list.md
│   │   ├── stats.md
│   │   ├── review.md
│   │   ├── deploy.md
│   │   └── preview.md
│   ├── skills/                  # 자동 호출
│   │   ├── auto-proofreader.md
│   │   └── auto-tagger.md
│   └── agents/                  # 명시적 호출
│       ├── proofreader.md
│       └── seo-optimizer.md
├── .github/workflows/
│   ├── deploy.yml               # Hugo 자동 배포
│   └── claude.yml               # @claude 멘션
├── content/posts/
├── scripts/
└── themes/PaperMod/
```

### CLAUDE.md

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
| /review | 문체/SEO 검토 |

## 글쓰기 규칙

@.claude/writing-guide.md
```

### settings.json (권한 + Hooks)

```json
{
  "permissions": {
    "allow": [
      "Bash(hugo:*)",
      "Bash(git add:*)",
      "Bash(git commit:*)",
      "Bash(git push:*)",
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

`git push` 전에 Hugo 빌드 테스트를 자동으로 실행한다. 빌드 실패 시 push가 차단된다.

### 역할 분담

| 유형 | 이름 | 역할 |
|------|------|------|
| Skill | auto-proofreader | 포스트 작성 시 자동 문체 검사 |
| Skill | auto-tagger | 내용 기반 태그 자동 추천 |
| Agent | proofreader | 심층 문체 검토 |
| Agent | seo-optimizer | SEO 분석 |

### 사용 예시

```bash
# 포스트 작성
"이 내용 정리해서 포스팅해줘"

# 슬래시 명령어
/post "제목" 태그1,태그2
/list
/stats

# 에이전트 호출
"proofreader로 최근 포스트 검토해줘"

# MCP 활용
"이 URL 내용 요약해서 TIL로 올려줘"

# GitHub에서
@claude 이 이슈 해결해줘
```

### 적용 결과

| 기능 | 효과 |
|------|------|
| CLAUDE.md | 프로젝트 컨텍스트 자동 로드 |
| Skills | 포스트 작성 시 자동 검사 |
| Hooks | 빌드 실패 방지 |
| MCP | 외부 URL/저장소 연동 |
| GitHub App | 이슈에서 바로 작업 |

---

## CLI 옵션 총정리

### 실행 모드

```bash
claude                    # 대화형
claude "작업"             # 단일 실행
claude -p "질문"          # 출력만 (파이프용)
claude -c                 # 최근 세션 계속
claude -r <id>            # 세션 복원
```

### 모델 및 도구

```bash
--model sonnet              # 모델 지정
--allowedTools "Bash,Read"  # 허용 도구
--disallowedTools "Write"   # 제한 도구
--max-turns 10              # 최대 턴 수
```

### 출력 포맷

```bash
--output-format text        # 텍스트 (기본)
--output-format json        # JSON
--output-format stream-json # 스트림 JSON
```

---

## 자주 쓰는 슬래시 명령어

| 명령어 | 기능 |
|--------|------|
| `/help` | 도움말 |
| `/model <name>` | 모델 변경 |
| `/compact` | 대화 압축 |
| `/clear` | 히스토리 초기화 |
| `/memory` | CLAUDE.md 편집 |
| `/vim` | Vim 모드 |
| `/rewind` | 변경 되돌리기 |
| `/agents` | 에이전트 관리 |
| `/hooks` | Hook 관리 |
| `/status` | 현재 상태 확인 |

---

## 성능 최적화 팁

### 1. 모델 선택

| 상황 | 추천 모델 |
|------|----------|
| 빠른 응답 필요 | `haiku` |
| 일반 코딩 | `sonnet` |
| 복잡한 분석 | `opus` |
| 대형 프로젝트 | `sonnet[1m]` |

### 2. 컨텍스트 관리

```bash
/compact    # 대화 압축
/clear      # 히스토리 초기화
```

### 3. 병렬 처리

`Ctrl+B`로 테스트나 빌드를 백그라운드에서 실행하면서 다른 작업을 계속한다.

### 4. 구체적인 프롬프트

```
❌ "버그 수정해줘"
✅ "src/auth.ts:45에서 발생하는 TypeError 수정해줘"
```

---

## 마무리

Claude Code는 단순한 코드 생성 도구가 아니다.

- **CLAUDE.md**로 프로젝트 컨텍스트를 공유
- **Skills/Agents**로 반복 작업 자동화
- **Hooks**로 실수 방지
- **MCP**로 외부 시스템 연동
- **GitHub App**으로 이슈/PR에서 바로 작업

이 기능들을 조합하면 진짜 AI 페어 프로그래머가 된다.

**핵심 파일**
- `CLAUDE.md` - 프로젝트 메모리
- `.claude/settings.json` - 권한 + Hooks
- `.claude/commands/` - 커스텀 명령어
- `.claude/skills/` - 자동 호출 기능
- `.claude/agents/` - 심층 분석 기능
- `.mcp.json` - MCP 서버 설정

**필수 단축키**
- `Tab` - Extended Thinking
- `Ctrl+B` - 백그라운드 실행
- `Esc` 2회 - 되돌리기
- `#` - 메모리 추가
