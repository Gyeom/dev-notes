---
name: auto-tagger
description: 포스트 내용을 분석하여 태그를 자동 추천한다. "포스트 작성", "태그 추천", "블로그에 올려" 같은 요청에 사용한다.
allowed-tools:
  - Read
  - Glob
---

# Auto Tagger Skill

포스트 내용을 분석하여 적절한 태그를 추천한다.

## 태그 분류

### 기술 태그
- 언어: Python, JavaScript, TypeScript, Go, Rust
- 프레임워크: React, Next.js, FastAPI, Django
- 도구: Docker, Git, Hugo, Vim
- 플랫폼: AWS, GCP, GitHub, Vercel

### 주제 태그
- TIL - 오늘 배운 것
- 트러블슈팅 - 문제 해결 기록
- 설정 - 환경 설정 관련
- 가이드 - 튜토리얼/설명서
- 회고 - 프로젝트/기간 회고

### 분야 태그
- 프론트엔드, 백엔드, DevOps, AI, 데이터베이스

## 동작

1. 포스트 본문에서 키워드 추출
2. 코드 블록의 언어 확인
3. 기존 포스트의 태그 패턴 참고 (content/posts/)
4. 3-7개 태그 추천
5. 사용자에게 확인 후 적용
