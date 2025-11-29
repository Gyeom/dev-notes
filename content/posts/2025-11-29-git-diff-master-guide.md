---
title: "Git Diff 완벽 가이드 - 파일 변경사항 추적의 모든 것"
date: 2025-11-29
draft: false
tags: ["Git", "diff", "버전관리", "개발도구"]
categories: ["개발"]
summary: "git diff의 기본부터 심화까지, 파일 변경사항을 효과적으로 추적하고 분석하는 방법"
---

Git의 diff 기능은 파일 변경사항을 추적하는 핵심 도구다. 기본 사용법은 간단하지만, 다양한 옵션과 활용법을 알면 개발 생산성이 크게 향상된다.

## 기본 사용법

### 작업 디렉토리 변경사항

```bash
# unstaged 변경사항 확인
git diff

# staged 변경사항 확인
git diff --staged
git diff --cached  # 동일한 명령어
```

### 특정 파일만 확인

```bash
git diff path/to/file.js
git diff src/components/*.tsx
```

### 커밋 간 비교

```bash
# 최근 커밋과 현재 작업 디렉토리 비교
git diff HEAD

# 특정 커밋 간 비교
git diff abc123 def456

# 브랜치 간 비교
git diff main feature-branch
```

## 출력 형식 옵션

### 통계 정보

```bash
# 변경된 파일 목록과 라인 수
git diff --stat

# 더 간결한 통계
git diff --shortstat

# 파일명만 출력
git diff --name-only

# 파일명과 상태(수정/추가/삭제)
git diff --name-status
```

예시 출력:

```
 src/app.js      | 15 +++++++++------
 src/utils.js    | 23 +++++++++++++++++++++++
 tests/app.test.js | 8 +++-----
 3 files changed, 35 insertions(+), 11 deletions(-)
```

### 컬러와 가독성

```bash
# 단어 단위로 변경사항 표시
git diff --word-diff

# 컬러 강제 적용 (파이프 사용 시 유용)
git diff --color=always | less -R

# 컬러 비활성화
git diff --no-color
```

## 고급 활용법

### 커밋 범위 지정

```bash
# HEAD부터 5개 전 커밋까지의 변경사항
git diff HEAD~5..HEAD

# 특정 브랜치의 최근 3개 커밋
git diff feature-branch~3..feature-branch

# 두 브랜치의 공통 조상 이후 변경사항
git diff main...feature-branch
```

`..`와 `...`의 차이:
- `A..B`: A와 B 사이의 모든 변경사항
- `A...B`: A와 B의 공통 조상부터 B까지의 변경사항

### 특정 파일/디렉토리만 비교

```bash
# 특정 디렉토리만
git diff HEAD -- src/

# 여러 파일
git diff HEAD -- file1.js file2.js

# 특정 확장자
git diff HEAD -- '*.js'
```

### 공백 무시

```bash
# 모든 공백 무시
git diff -w
git diff --ignore-all-space

# 라인 끝 공백 무시
git diff --ignore-space-at-eol

# 공백 변경만 표시
git diff --ignore-blank-lines
```

리팩토링이나 코드 포맷팅 후 실질적인 변경사항만 확인할 때 유용하다.

## 컨텍스트 조정

```bash
# 변경 부분 전후 10줄씩 표시 (기본: 3줄)
git diff -U10

# 함수/클래스 이름 표시
git diff --function-context
git diff -W
```

큰 파일에서 변경 위치를 파악할 때 컨텍스트를 늘리면 좋다.

## 바이너리 파일 처리

```bash
# 바이너리 파일 변경 여부만 표시
git diff --binary

# 바이너리 파일 무시
git diff --no-binary
```

이미지나 컴파일된 파일이 많을 때 출력을 깔끔하게 유지할 수 있다.

## 외부 도구 연동

### 시각적 diff 도구

```bash
# 설정된 외부 도구로 열기
git difftool

# 특정 도구 지정
git difftool --tool=vimdiff
git difftool --tool=meld

# 사용 가능한 도구 목록
git difftool --tool-help
```

### 설정 예시

```bash
# 기본 diff 도구 설정
git config --global diff.tool vimdiff

# 외부 도구 자동으로 열기 (확인 없이)
git config --global difftool.prompt false
```

## 실전 활용 패턴

### PR 리뷰 준비

```bash
# PR에 포함될 변경사항 통계
git diff --stat main...feature-branch

# 특정 파일의 상세 변경사항
git diff main...feature-branch -- src/critical.js
```

### 마지막 배포 이후 변경사항

```bash
# 프로덕션 태그 이후 모든 변경사항
git diff v1.0.0..HEAD

# 파일별 변경 라인 수
git diff v1.0.0..HEAD --stat
```

### 충돌 분석

```bash
# merge/rebase 중 충돌 확인
git diff --ours    # 현재 브랜치 버전
git diff --theirs  # 머지하려는 브랜치 버전
git diff --base    # 공통 조상 버전
```

### 코드 리뷰용 출력

```bash
# HTML 형식으로 변환 (외부 도구 필요)
git diff HEAD~1 | diff2html -i stdin -o stdout > changes.html

# 패치 파일 생성
git diff > changes.patch
git apply changes.patch  # 적용
```

## 성능 최적화

### 대용량 저장소에서

```bash
# 경로 제한으로 속도 향상
git diff HEAD -- src/

# 특정 타입 파일만
git diff HEAD -- '*.go'

# 리네임 감지 비활성화 (속도 향상)
git diff --no-renames
```

### 리네임 감지 조정

```bash
# 리네임 감지 (기본 활성화)
git diff -M

# 리네임 감지 임계값 조정 (50% 유사도)
git diff -M50%

# 복사 감지
git diff -C
```

## 출력 커스터마이징

### Alias 설정

```bash
# 자주 쓰는 명령어를 짧게
git config --global alias.ds 'diff --stat'
git config --global alias.dw 'diff --word-diff'
git config --global alias.dc 'diff --cached'

# 사용: git ds
```

### 컬러 설정

```bash
# diff 컬러 커스터마이징
git config --global color.diff.meta "blue bold"
git config --global color.diff.old "red bold"
git config --global color.diff.new "green bold"
```

## 스크립트 활용

### 변경 라인 수 계산

```bash
# 추가/삭제 라인 수
git diff --shortstat
# 예시: 3 files changed, 35 insertions(+), 11 deletions(-)

# 숫자만 추출
git diff --numstat
```

### 변경된 파일 목록을 다른 명령어에 전달

```bash
# 변경된 파일 lint 검사
git diff --name-only | xargs eslint

# staged 파일만 테스트
git diff --cached --name-only '*.test.js' | xargs jest
```

## 트러블슈팅

### diff가 너무 느릴 때

```bash
# 리네임 감지 비활성화
git diff --no-renames

# 경로 제한
git diff HEAD -- specific/path/
```

### 줄바꿈 문제 (Windows/Mac/Linux)

```bash
# 줄바꿈 차이 무시
git diff --ignore-cr-at-eol

# autocrlf 설정 확인
git config core.autocrlf
```

### 대용량 파일 diff

```bash
# 특정 크기 이상 파일 제외
git diff -- . ':(exclude)*.bin' ':(exclude)*.zip'
```

## diff 출력 이해하기

기본 diff 출력 형식:

```diff
diff --git a/file.js b/file.js
index abc123..def456 100644
--- a/file.js
+++ b/file.js
@@ -10,7 +10,8 @@ function example() {
   const oldLine = 'removed';
-  const removed = 'this line is deleted';
+  const added = 'this line is new';
+  const another = 'another new line';
   return result;
 }
```

- `---`: 이전 버전
- `+++`: 새 버전
- `@@`: 변경 위치 (줄 번호)
- `-`: 삭제된 줄
- `+`: 추가된 줄
- 공백: 변경 없음 (컨텍스트)

## 정리

Git diff는 단순한 비교 도구를 넘어 코드 변경 히스토리를 이해하는 핵심 도구다.

핵심 명령어:
- `git diff --stat`: 빠른 변경 통계
- `git diff --word-diff`: 정밀한 비교
- `git diff main...feature`: 브랜치 간 차이
- `git diff -w`: 공백 무시
- `git difftool`: 시각적 비교

상황에 맞는 옵션을 조합하면 코드 리뷰, 디버깅, 배포 준비 등 모든 개발 단계에서 효율이 향상된다.
