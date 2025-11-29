# Dev Notes

Hugo 기반 개발 블로그. 마크다운 작성 후 push하면 자동 배포된다.

## 빌드 및 배포

```bash
hugo --gc --minify        # 빌드
hugo server -D            # 로컬 미리보기 (http://localhost:1313/dev-notes/)
git push                  # 배포 (GitHub Actions 자동 실행)
```

## 슬래시 명령어

| 명령어 | 설명 |
|--------|------|
| `/post` | 새 포스트 작성 |
| `/draft` | 초안 작성 (draft: true) |
| `/publish` | 초안을 발행 |
| `/edit` | 기존 포스트 수정 |
| `/delete` | 포스트 삭제 |
| `/list` | 최근 포스트 목록 |
| `/stats` | 블로그 통계 |
| `/tag` | 태그 조회 및 관리 |
| `/backup` | 포스트 백업 |
| `/review` | 포스트 문체/SEO 검토 |
| `/sync` | 작업 내용과 관련된 포스트 확인 |
| `/index` | 포스트 인덱스 갱신 |
| `/pr` | 변경사항을 PR로 생성 (권장) |
| `/deploy` | 변경사항 직접 배포 (main에 바로 push) |
| `/preview` | 로컬 미리보기 |
| `/screenshot` | 웹 페이지 스크린샷 캡처 |

## 배포 워크플로우

**권장: PR 기반 배포**
```
포스트 작성/수정 → /pr → PR에서 리뷰/보완 → merge → 자동 배포
```

- `/pr` 사용 시 PR에서 `@claude 보완해줘` 등으로 추가 수정 가능
- merge 후 GitHub Actions가 자동 배포

**빠른 배포 (리뷰 불필요 시)**
```
포스트 작성/수정 → /deploy → main에 직접 push → 자동 배포
```

## MCP 서버

| MCP | 설명 | 활용 예시 |
|-----|------|----------|
| `fetch` | URL 내용 가져오기 | "이 URL 내용 요약해서 포스팅해줘" |
| `github` | GitHub 저장소 관리 | "최근 이슈 확인해줘", "PR 상태 알려줘" |
| `playwright` | 브라우저 자동화 | 스크린샷 캡처, 웹 페이지 조작 |

### Playwright 스크린샷 가이드

스크린샷 캡처 시 불필요한 공백을 줄이려면 viewport를 콘텐츠에 맞게 조정한다.

```javascript
// 1. viewport 크기 조정 (캡처 전)
browser_resize({ width: 1200, height: 600 })

// 2. 스크린샷 캡처
browser_take_screenshot({ filename: "screenshot.png" })

// 3. 특정 요소만 캡처 (권장)
browser_take_screenshot({
  element: "main content",
  ref: "main",
  filename: "element.png"
})
```

권장 viewport 높이:
- 목록 페이지 (이슈, PR): 400-500px
- 상세 페이지: 600-700px
- 전체 페이지: `fullPage: true` 사용

## Skills (자동 호출)

Claude가 상황에 맞게 자동으로 사용한다.

| Skill | 설명 |
|-------|------|
| `auto-proofreader` | 포스트 작성 시 기본 문체 검사 |
| `auto-tagger` | 내용 기반 태그 자동 추천 |
| `post-sync` | 작업 완료 후 관련 포스트 업데이트 확인 |

## Agents (명시적 호출)

상세 분석이 필요할 때 직접 호출한다.

```
proofreader 에이전트로 이 포스트 검토해줘
seo-optimizer로 SEO 분석해줘
```

| Agent | 설명 |
|-------|------|
| `proofreader` | 글쓰기 가이드 기반 심층 문체 검토 |
| `seo-optimizer` | 제목/요약/태그/본문 SEO 분석 |
| `post-reviewer` | 종합 검토 (문체 + SEO + 코드) |

## 프로젝트 구조

```
content/posts/    # 블로그 포스트
scripts/
  lib/            # 공통 유틸리티
  new-post.sh     # 새 포스트 생성
  auto-post.sh    # 자동 포스팅
  capture-screenshots.js  # 스크린샷 캡처
.claude/
  commands/       # 슬래시 명령어
  skills/         # 자동 호출 스킬
  agents/         # 명시적 호출 에이전트
  knowledge/      # 포스트 인덱스, 참조 데이터
  writing-guide.md
.mcp.json         # MCP 서버 설정
themes/PaperMod/  # Hugo 테마
```

## 글쓰기 규칙

@.claude/writing-guide.md

## 작업 후 포스트 동기화

`post-sync` Skill이 자동으로 실행된다. 커밋, 배포, 기능 추가 등 의미 있는 작업 완료 시 관련 포스트 업데이트 필요성을 확인한다.

- `/sync` 명령어로 명시적 확인 가능
- `.claude/knowledge/post-index.md` 참조

## Hooks

- **PreToolUse (git push)**: 배포 전 Hugo 빌드 테스트 자동 실행
- **PostToolUse (Write posts)**: 포스트 작성 후 다음 단계 안내
- **PostToolUse (Edit posts)**: 포스트 수정 후 미리보기 안내

## Knowledge Base

`.claude/knowledge/post-index.md`에 포스트 인덱스가 저장된다.
- `/index` 명령어로 갱신
- 태그별 분류, 시리즈 정보 포함
- 포스트 검색 및 연결 시 참조

## 사이트 URL

https://gyeom.github.io/dev-notes/
