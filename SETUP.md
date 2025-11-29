# Dev Notes 설정 가이드

## 1. GitHub 저장소 생성

```bash
# GitHub CLI 로그인 (처음 한 번만)
gh auth login

# 저장소 생성 및 푸시
cd ~/dev-notes
gh repo create dev-notes --public --source=. --push
```

또는 GitHub 웹사이트에서:
1. https://github.com/new 접속
2. Repository name: `dev-notes` 입력
3. Public 선택 후 Create repository

## 2. 설정 파일 수정

`hugo.toml` 파일에서 USERNAME을 본인의 GitHub 사용자명으로 변경:

```bash
# 예시: 사용자명이 "john"인 경우
sed -i '' 's/USERNAME/john/g' hugo.toml
```

## 3. GitHub Pages 활성화

1. GitHub 저장소 → Settings → Pages
2. Source: `GitHub Actions` 선택
3. Save

## 4. 첫 배포

```bash
cd ~/dev-notes
git add .
git commit -m "Initial commit: Dev Notes setup"
git push -u origin main
```

푸시하면 GitHub Actions가 자동으로 사이트를 빌드하고 배포합니다.

## 5. 사이트 확인

배포 완료 후: `https://USERNAME.github.io/dev-notes/`

---

## 사용 방법

### 새 포스트 작성 (수동)

```bash
cd ~/dev-notes
./scripts/new-post.sh "포스트 제목" "태그1,태그2" "카테고리"
```

### 자동 포스팅 (내용 파이프)

```bash
# 텍스트 파이프로 전달
echo "포스트 내용입니다." | ./scripts/auto-post.sh "제목" "태그" "카테고리"

# 파일에서 읽어서 전달
cat my-content.md | ./scripts/auto-post.sh "제목" "태그" "카테고리"

# 자동 푸시까지
AUTO_PUSH=true cat my-content.md | ./scripts/auto-post.sh "제목" "태그" "카테고리"
```

### Claude와 함께 사용

Claude가 정리한 내용을 파일로 저장 후:
```bash
cat claude-output.md | AUTO_PUSH=true ./scripts/auto-post.sh "Claude가 정리한 내용" "AI,개발" "TIL"
```

### 로컬 미리보기

```bash
cd ~/dev-notes
hugo server -D
# http://localhost:1313/dev-notes/ 에서 확인
```

---

## 프로젝트 구조

```
dev-notes/
├── content/
│   └── posts/          # 블로그 포스트
├── scripts/
│   ├── new-post.sh     # 새 포스트 템플릿 생성
│   └── auto-post.sh    # 자동 포스팅 스크립트
├── themes/
│   └── PaperMod/       # Hugo 테마
├── .github/
│   └── workflows/
│       └── deploy.yml  # 자동 배포 설정
└── hugo.toml           # 사이트 설정
```
