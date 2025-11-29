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
| `/post` | 새 포스트 작성 및 배포 |
| `/draft` | 초안 작성 (draft: true) |
| `/publish` | 초안을 발행 |
| `/edit` | 기존 포스트 수정 |
| `/list` | 최근 포스트 목록 |
| `/stats` | 블로그 통계 |
| `/review` | 포스트 문체/SEO 검토 |
| `/deploy` | 변경사항 배포 |
| `/preview` | 로컬 미리보기 |

## 에이전트

| 에이전트 | 설명 |
|----------|------|
| `proofreader` | 글쓰기 가이드 기반 문체 검토 |
| `seo-optimizer` | 제목/요약/태그 SEO 최적화 |

## 프로젝트 구조

```
content/posts/    # 블로그 포스트
scripts/          # 자동화 스크립트
.claude/
  commands/       # 슬래시 명령어
  agents/         # 커스텀 에이전트
  writing-guide.md
themes/PaperMod/  # Hugo 테마
```

## 글쓰기 규칙

@.claude/writing-guide.md

## Hooks

- **PreToolUse (git push)**: 배포 전 Hugo 빌드 테스트 자동 실행
- **PostToolUse (Write posts)**: 포스트 작성 후 안내 메시지

## 사이트 URL

https://gyeom.github.io/dev-notes/
