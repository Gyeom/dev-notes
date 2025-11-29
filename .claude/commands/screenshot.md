# /screenshot <URL> [파일명] [높이]

웹 페이지 스크린샷을 캡처한다.

## 인자
- URL: 캡처할 페이지 주소 (필수)
- 파일명: 저장할 파일명 (선택, 기본값: screenshot-{timestamp}.png)
- 높이: viewport 높이 (선택, 기본값: 600)

## 실행 단계

1. Playwright로 URL 접속
2. viewport 크기 조정 (width: 1200, height: $ARGUMENTS[2] 또는 600)
3. 페이지 로딩 대기 (2초)
4. 스크린샷 캡처
5. static/images/ 폴더에 저장
6. 브라우저 종료

## 예시

```
/screenshot https://github.com/user/repo/issues issue-list 450
/screenshot https://example.com
```

## 권장 높이

- 목록 페이지 (이슈, PR): 400-500
- 상세 페이지: 600-700
- 전체 페이지: fullPage 옵션 사용

## 주의사항

- 캡처 전 viewport를 조정해 불필요한 공백을 방지한다
- 특정 요소만 캡처하려면 element/ref 옵션을 사용한다
