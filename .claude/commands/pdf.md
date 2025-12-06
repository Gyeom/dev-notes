# /pdf: 페이지를 PDF로 변환

About 페이지(이력서)를 PDF로 변환한다. 네비게이션 숨김, 폰트 크기 조정, 페이지 분리가 자동 적용된다.

## 사용법

```
/pdf [URL]
```

- URL 생략 시 기본값: `http://localhost:1313/dev-notes/about/`
- 로컬 Hugo 서버가 실행 중이어야 한다 (`hugo server -D`)

## 인자

$ARGUMENTS

## 실행 단계

1. **Hugo 서버 확인**: 로컬 서버가 실행 중인지 확인한다. 실행 중이 아니면 시작을 안내한다.

2. **Playwright로 페이지 열기**:
   ```
   mcp__playwright__browser_navigate로 URL 접속
   ```

3. **스타일 적용 + PDF 생성** (browser_run_code):
   ```javascript
   // 스타일 적용 (고정 폰트 크기로 빠르게 처리)
   await page.evaluate(() => {
     // 네비게이션 숨김
     const header = document.querySelector('header');
     if (header) header.style.display = 'none';
     const pageTitle = document.querySelector('h1.post-title');
     if (pageTitle) pageTitle.style.display = 'none';

     // 고정 폰트 크기 76%
     document.body.style.fontSize = '76%';
     document.body.style.lineHeight = '1.3';

     // 마진 축소
     document.querySelectorAll('h2').forEach(h2 => {
       h2.style.marginTop = '0.4em';
       h2.style.marginBottom = '0.2em';
     });
     document.querySelectorAll('hr').forEach(hr => {
       hr.style.margin = '0.4em 0';
     });

     // 페이지 분리
     document.querySelectorAll('h2').forEach(h2 => {
       if (h2.textContent.includes('Experience') ||
           h2.textContent.includes('Activity')) {
         h2.style.pageBreakBefore = 'always';
       }
     });

     document.querySelectorAll('.company-header').forEach(header => {
       const h3 = header.querySelector('h3');
       if (h3 && h3.textContent.includes('한화솔루션')) {
         header.style.pageBreakBefore = 'always';
       }
     });

     // 항목 끊김 방지
     document.querySelectorAll('.project, .activity-item, .achievement, tr').forEach(el => {
       el.style.pageBreakInside = 'avoid';
     });
   });

   await page.pdf({
     path: '/Users/a13801/dev-notes/resume.pdf',
     format: 'A4',
     margin: { top: '1cm', right: '1cm', bottom: '1cm', left: '1cm' },
     printBackground: true
   });
   ```

4. **결과 안내**: PDF 파일 경로와 페이지 수 알려주기

## 페이지 분리 전략

| 페이지 | 내용 |
|--------|------|
| 1 | Header + Core Competencies + Tech Stack |
| 2 | Experience (42dot) |
| 3 | Experience (한화솔루션, 롯데정보통신) |
| 4 | Activity + Education |

## 커스터마이징

- **파일명 변경**: `path` 옵션 수정
- **폰트 크기**: `fontSize = '76%'` 변경 (Tech Stack이 1페이지에 들어가도록 조정됨)
- **여백 조정**: `margin` 옵션 수정
- **페이지 분리 위치**: `page.evaluate` 내 조건문 수정

## 참고

- Playwright MCP의 `browser_run_code`로 `page` 객체에 접근
- `@media print` 스타일이 about.md에 정의되어 있음
- 프로젝트/성과 항목은 `page-break-inside: avoid`로 중간에 잘리지 않음
