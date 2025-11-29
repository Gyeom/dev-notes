# Dev Notes

Hugo 기반 개발 블로그. 마크다운 작성 후 push하면 자동 배포된다.

## 빌드 및 배포

```bash
hugo --gc --minify        # 빌드
hugo server -D            # 로컬 미리보기 (http://localhost:1313/dev-notes/)
git push                  # 배포 (GitHub Actions 자동 실행)
```

## 포스트 작성

```bash
# 새 포스트 생성
./scripts/new-post.sh "제목" "태그1,태그2" "카테고리"

# 내용 파이프로 자동 포스팅
echo "내용" | ./scripts/auto-post.sh "제목" "태그"

# 자동 배포까지
echo "내용" | AUTO_PUSH=true ./scripts/auto-post.sh "제목" "태그"
```

## 프로젝트 구조

```
content/posts/    # 블로그 포스트
scripts/          # 자동화 스크립트
themes/PaperMod/  # Hugo 테마
```

## 글쓰기 규칙

@.claude/writing-guide.md

## 사이트 URL

https://gyeom.github.io/dev-notes/
