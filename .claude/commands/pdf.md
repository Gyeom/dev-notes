# /pdf: 이력서를 PDF로 변환

이력서 페이지를 PDF로 변환한다. Hugo Book 테마에 최적화되어 있다.

## 사용법

```
/pdf [URL]
```

- URL 생략 시 기본값: `http://localhost:1314/docs/resume/`
- 로컬 Hugo 서버가 실행 중이어야 한다 (`cd ~/dev-notes-private && hugo server -D -p 1314`)

## 인자

$ARGUMENTS

## 실행 단계

1. **Hugo 서버 확인**: localhost:1314가 실행 중인지 확인. 아니면 시작 안내.

2. **Playwright로 페이지 열기**:
   ```
   mcp__playwright__browser_navigate로 URL 접속
   ```

3. **스타일 적용 + PDF 생성** (browser_run_code):
   ```javascript
   async (page) => {
     await page.evaluate(() => {
       // Hugo Book 사이드바/메뉴 숨김
       document.querySelectorAll('aside, nav.book-menu, .book-toc').forEach(el => {
         el.style.display = 'none';
       });

       // 메인 콘텐츠 전체 너비
       const main = document.querySelector('main');
       if (main) {
         main.style.maxWidth = '100%';
         main.style.padding = '0';
       }

       const article = document.querySelector('article');
       if (article) {
         article.style.maxWidth = '800px';
         article.style.margin = '0 auto';
       }

       // 앵커 링크 숨김
       document.querySelectorAll('a.anchor').forEach(a => a.style.display = 'none');

       // 하단 네비게이션 숨김
       document.querySelectorAll('a[href*="shinhan"]').forEach(a => {
         if (a.closest('article')) a.style.display = 'none';
       });

       // Experience 섹션 앞에서 페이지 분리
       document.querySelectorAll('h2').forEach(h2 => {
         if (h2.textContent.includes('Experience')) {
           h2.style.pageBreakBefore = 'always';
         }
       });
     });

     await page.pdf({
       path: '/Users/a13801/dev-notes-private/resume.pdf',
       format: 'A4',
       margin: { top: '1.5cm', right: '1.5cm', bottom: '1.5cm', left: '1.5cm' },
       printBackground: true
     });

     return 'PDF saved to ~/dev-notes-private/resume.pdf';
   }
   ```

4. **결과 안내**: PDF 파일 경로 알려주기

## 페이지 분리 전략

| 페이지 | 내용 |
|--------|------|
| 1 | Header + Core Competencies + Tech Stack |
| 2~ | Experience (42dot, 한화솔루션, 롯데정보통신) |
| 마지막 | Activity + Education |

## 커스터마이징

- **파일명 변경**: `path` 옵션 수정
- **여백 조정**: `margin` 옵션 수정
- **페이지 분리 위치**: `page.evaluate` 내 조건문 수정

## 참고

- Playwright MCP의 `browser_run_code`로 `page` 객체에 접근
- 이력서 스타일은 `content/docs/resume/_index.md`에 정의
- `@media print` 스타일이 이력서 파일에 포함되어 있음
