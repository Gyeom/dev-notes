---
title: "Claude Code 완벽 가이드 2025 - 입문부터 고급 활용까지"
date: 2024-11-29
draft: false
tags: ["Claude Code", "AI", "개발도구", "자동화", "MCP", "가이드"]
categories: ["개발환경"]
summary: "2025년 11월 기준 Claude Code의 모든 기능을 정리한 종합 가이드. 설치부터 고급 자동화까지."
---

## 개요

Claude Code는 Anthropic의 공식 CLI 기반 AI 코딩 어시스턴트다. 터미널에서 직접 코드를 읽고, 수정하고, 명령어를 실행할 수 있다. 이 가이드는 2025년 11월 기준 최신 기능을 모두 다룬다.

**이 가이드에서 다루는 내용**
- 기본 사용법과 단축키
- 프로젝트 설정 (CLAUDE.md, settings.json)
- 커스텀 슬래시 명령어
- Hooks로 자동화
- MCP 서버 연동
- GitHub Actions 통합
- 성능 최적화 팁

---

## 1. 설치 및 시작

### 설치

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

## 2. 필수 단축키

외우면 생산성이 크게 올라간다.

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

### Vim 모드

```bash
/vim    # Vim 키바인딩 활성화
```

---

## 3. 모델 선택

### 사용 가능한 모델

| 모델 | 용도 |
|------|------|
| `sonnet` | 일반 코딩 (기본값, 빠름) |
| `opus` | 복잡한 분석 (느리지만 강력) |
| `haiku` | 간단한 작업 (가장 빠름) |
| `opusplan` | Opus로 계획 → Sonnet으로 실행 |
| `sonnet[1m]` | 100만 토큰 컨텍스트 (대형 프로젝트) |

### 모델 변경

```bash
# CLI 옵션
claude --model opus

# 세션 중
/model sonnet

# 환경변수
export ANTHROPIC_MODEL=sonnet
```

### Extended Thinking

복잡한 문제는 `Tab`을 눌러 활성화하거나 프롬프트에 "think hard"를 추가한다.

---

## 4. 프로젝트 설정

### CLAUDE.md - 프로젝트 메모리

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

## 프로젝트 구조
- src/components/ - UI 컴포넌트
- src/utils/ - 유틸리티 함수
- src/types/ - 타입 정의

## 규칙
- console.log 대신 logger 사용
- any 타입 금지
```

### 파일 임포트

다른 파일을 참조할 수 있다.

```markdown
## 글쓰기 규칙

@.claude/writing-guide.md
```

최대 5단계까지 재귀적으로 참조 가능하다.

### 메모리 계층

Claude는 다음 순서로 설정을 로드한다.

1. `~/.claude/CLAUDE.md` - 전역 (모든 프로젝트)
2. `./CLAUDE.md` - 프로젝트 (팀 공유)
3. 세션 중 `#`으로 추가한 내용

---

## 5. 권한 설정

### .claude/settings.json

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

예시:
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

## 6. 커스텀 슬래시 명령어

### 명령어 만들기

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

다음을 확인한다:
- 보안 취약점
- 성능 이슈
- 코드 스타일
```

### 사용

```bash
/review src/auth.ts
```

### 인자 접근

- `$ARGUMENTS` - 전체 인자
- `$1`, `$2` - 위치별 인자

---

## 7. Hooks - 자동화의 핵심

### Hooks란?

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
        "matchers": ["Bash"],
        "type": "command",
        "command": "./scripts/validate-command.sh"
      }
    ]
  }
}
```

### 실전 예제: 자동 포매팅

`scripts/auto-format.sh`:

```bash
#!/bin/bash
if [[ "$TOOL_NAME" == "Edit" ]]; then
  prettier --write "$FILE_PATH" 2>/dev/null
fi
exit 0
```

### 반환값

- `0` - 성공
- `2` - 작업 차단 (stderr 메시지 표시)
- 기타 - 경고 후 계속 진행

---

## 8. MCP 서버 연동

### MCP란?

Model Context Protocol. 외부 도구와 데이터 소스를 Claude에 연결한다.

### 서버 추가

```bash
# HTTP 서버
claude mcp add --transport http notion https://mcp.notion.com/mcp

# 로컬 서버
claude mcp add --transport stdio postgres -- npx -y postgresql-mcp
```

### 관리 명령어

```bash
claude mcp list          # 설치된 서버 목록
claude mcp get <name>    # 상세 정보
claude mcp remove <name> # 제거
```

### 설정 파일

`.mcp.json`:

```json
{
  "mcpServers": {
    "github": {
      "url": "https://mcp.github.com/mcp"
    },
    "postgres": {
      "command": "npx",
      "args": ["-y", "postgresql-mcp"],
      "env": {
        "DATABASE_URL": "${DATABASE_URL}"
      }
    }
  }
}
```

### 활용 예시

```bash
# JIRA 이슈 기반 개발
> JIRA ENG-123 이슈를 구현하고 PR 생성해줘

# Sentry 에러 분석
> 지난 24시간 Sentry 에러 중 가장 많이 발생한 것 분석해줘

# 데이터베이스 쿼리
> users 테이블에서 최근 가입자 10명 조회해줘
```

---

## 9. Subagents - 전문 에이전트

### 기본 에이전트

```bash
/agents
```

- **General-purpose** - 복잡한 다단계 작업
- **Explore** - 코드베이스 탐색 (읽기 전용)
- **Debugger** - 에러 분석

### 커스텀 에이전트 만들기

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

# Security Reviewer

보안 관점에서 코드를 분석합니다.
```

### 사용

```bash
> security-reviewer 에이전트로 src/auth/ 폴더 검토해줘
```

---

## 10. GitHub 연동

### GitHub Actions 설정

`.github/workflows/claude.yml`:

```yaml
name: Claude AI Assistant
on:
  issue_comment:
    types: [created]
  pull_request_review_comment:
    types: [created]

jobs:
  claude:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: anthropics/claude-code-action@v1
        with:
          prompt: ${{ github.event.comment.body }}
          claude_args: "--max-turns 5"
        env:
          ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
```

### 사용

PR이나 이슈에서:

```
@claude 이 버그 수정해줘
@claude 테스트 추가해줘
@claude 코드 리뷰해줘
```

---

## 11. CLI 옵션 총정리

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
--model sonnet            # 모델 지정
--allowedTools "Bash,Read"  # 허용 도구
--disallowedTools "Write"   # 제한 도구
--max-turns 10            # 최대 턴 수
```

### 출력 포맷

```bash
--output-format text      # 텍스트 (기본)
--output-format json      # JSON
--output-format stream-json  # 스트림 JSON
```

### 시스템 프롬프트

```bash
--system-prompt "..."           # 전체 대체
--append-system-prompt "..."    # 기존에 추가 (권장)
```

---

## 12. 성능 최적화

### 1. 모델 선택

| 상황 | 추천 모델 |
|------|----------|
| 빠른 응답 필요 | `haiku` |
| 일반 코딩 | `sonnet` |
| 복잡한 분석 | `opus` |
| 대형 프로젝트 | `sonnet[1m]` |
| 비용 절감 | `opusplan` |

### 2. 컨텍스트 관리

```bash
/compact    # 대화 압축
/clear      # 히스토리 초기화
```

### 3. 병렬 처리

`Ctrl+B`로 테스트나 빌드를 백그라운드에서 실행하면서 다른 작업을 계속할 수 있다.

### 4. 권한 사전 설정

자주 쓰는 명령어는 `allow`에 추가해서 매번 승인하지 않게 한다.

```json
{
  "permissions": {
    "allow": [
      "Bash(npm test:*)",
      "Bash(npm run build:*)"
    ]
  }
}
```

### 5. 구체적인 프롬프트

```
❌ "버그 수정해줘"
✅ "src/auth.ts:45에서 발생하는 TypeError 수정해줘. 에러 메시지: Cannot read property 'id' of undefined"
```

---

## 13. 자주 쓰는 슬래시 명령어

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
| `/init` | CLAUDE.md 초기화 |
| `/install-github-app` | GitHub 앱 설치 |

---

## 14. 문제 해결

### "Permission denied" 에러

권한 설정 확인.

```bash
# 현재 권한 확인
cat .claude/settings.json

# 필요한 권한 추가
```

### 느린 응답

1. 모델을 `sonnet`이나 `haiku`로 변경
2. `/compact`로 컨텍스트 압축
3. 불필요한 MCP 서버 제거

### 세션 복원 안 됨

```bash
# 세션 목록 확인
claude --list-sessions

# 특정 세션 복원
claude -r <session-id>
```

---

## 마무리

Claude Code는 단순한 코드 생성 도구가 아니다. CLAUDE.md로 프로젝트 컨텍스트를 공유하고, Hooks로 워크플로우를 자동화하고, MCP로 외부 시스템과 연동하면 진짜 AI 페어 프로그래머가 된다.

**핵심 설정 파일**
- `CLAUDE.md` - 프로젝트 메모리
- `.claude/settings.json` - 권한 설정
- `.claude/commands/` - 커스텀 명령어
- `.mcp.json` - MCP 서버 설정

**필수 단축키**
- `Tab` - Extended Thinking
- `Ctrl+B` - 백그라운드 실행
- `Esc` 2회 - 되돌리기
- `#` - 메모리 추가

이 가이드의 내용을 프로젝트에 적용해보자.
