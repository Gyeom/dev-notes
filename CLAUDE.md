# Claude Code 프로젝트 가이드

이 프로젝트는 Hugo 기반 개발 블로그다.

## 프로젝트 구조

```
dev-notes/
├── content/posts/     # 블로그 포스트 (마크다운)
├── scripts/           # 자동화 스크립트
├── .claude/           # Claude 설정
│   ├── settings.json  # 프로젝트 설정
│   └── writing-guide.md  # 글쓰기 가이드
└── hugo.toml          # Hugo 설정
```

## 포스트 작성

### 새 포스트 생성
```bash
./scripts/new-post.sh "제목" "태그1,태그2" "카테고리"
```

### 내용을 받아서 자동 포스팅
```bash
echo "내용" | ./scripts/auto-post.sh "제목" "태그" "카테고리"
```

### 자동 배포까지
```bash
echo "내용" | AUTO_PUSH=true ./scripts/auto-post.sh "제목" "태그"
```

## 글쓰기 규칙

`.claude/writing-guide.md` 참고. 핵심 규칙:

- **~다 체** 사용
- `:` 로 문장 끝내지 않기
- 간결하고 직접적인 표현
- 코드 블록에 언어 명시

## 배포

main 브랜치에 push하면 GitHub Actions가 자동 배포한다.

```bash
git add . && git commit -m "Add: 포스트 제목" && git push
```

## 로컬 미리보기

```bash
hugo server -D
# http://localhost:1313/dev-notes/
```

## 사이트 URL

https://gyeom.github.io/dev-notes/
