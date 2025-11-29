---
description: 변경사항을 GitHub에 배포한다
allowed-tools:
  - Bash
---

현재 변경사항을 GitHub에 푸시하여 블로그를 배포한다.

## 순서

1. `git status`로 변경사항 확인
2. `hugo --gc --minify`로 빌드 테스트
3. 빌드 성공 시:
   - `git add .`
   - `git commit -m "적절한 커밋 메시지"`
   - `git push`
4. 배포 완료 후 사이트 URL 안내: https://gyeom.github.io/dev-notes/

## 커밋 메시지 규칙

- 새 포스트: `Add: 포스트 제목`
- 수정: `Update: 수정 내용`
- 삭제: `Remove: 삭제 내용`
- 설정 변경: `Chore: 변경 내용`
