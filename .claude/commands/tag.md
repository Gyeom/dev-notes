---
description: 태그를 조회하고 관리한다
allowed-tools:
  - Read
  - Bash
  - Glob
  - Edit
argument-hint: [list|rename|add|remove] [옵션]
---

블로그 태그를 조회하고 관리한다.

## 명령어

### 태그 목록 조회 (기본)
```
/tag
/tag list
```
모든 태그와 사용 횟수를 보여준다.

### 태그 이름 변경
```
/tag rename <기존태그> <새태그>
```
모든 포스트에서 태그 이름을 일괄 변경한다.

### 태그 추가
```
/tag add <태그> <검색어>
```
검색된 포스트에 태그를 추가한다.

### 태그 제거
```
/tag remove <태그> [검색어]
```
태그를 제거한다. 검색어가 없으면 모든 포스트에서 제거.

## 출력 예시

```
📊 태그 현황

| 태그 | 포스트 수 |
|------|----------|
| Hugo | 2 |
| Claude Code | 2 |
| GitHub Actions | 1 |
| 자동화 | 3 |

총 15개 태그, 4개 포스트
```

## 인자

- $1: 명령어 (list, rename, add, remove)
- $2~: 명령어별 옵션
