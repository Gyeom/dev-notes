---
description: Private repo 변경사항을 GitHub에 푸시한다
allowed-tools:
  - Bash
---

Private repo (temp/) 변경사항을 GitHub에 푸시한다.

## 순서

1. `cd temp && git status`로 변경사항 확인
2. 변경사항이 있으면:
   - `git add .`
   - `git commit -m "적절한 커밋 메시지"`
   - `git push`
3. 완료 후 안내

## 커밋 메시지 규칙

- 새 문서: `Add: 문서 제목`
- 수정: `Update: 수정 내용`
- 삭제: `Remove: 삭제 내용`

## 참고

- Private repo는 GitHub Pages 배포 없음 (로컬 전용)
- Preview: `cd temp && hugo server -D -p 1314`
