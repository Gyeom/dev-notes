const { chromium } = require('@playwright/test');

async function captureScreenshots() {
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({
    viewport: { width: 1280, height: 800 },
    deviceScaleFactor: 2,
  });
  const page = await context.newPage();

  const outputDir = '/Users/a13801/dev-notes/static/images/github-claude-automation';

  // 1. 이슈 목록
  console.log('Capturing issues list...');
  await page.goto('https://github.com/Gyeom/dev-notes/issues');
  await page.waitForLoadState('networkidle');
  await page.screenshot({ path: `${outputDir}/01-issues-list.png` });

  // 2. 이슈 #3 상세 (Claude 멘션)
  console.log('Capturing issue #3...');
  await page.goto('https://github.com/Gyeom/dev-notes/issues/3');
  await page.waitForLoadState('networkidle');
  await page.screenshot({ path: `${outputDir}/02-issue-detail.png`, fullPage: true });

  // 3. PR 목록
  console.log('Capturing PR list...');
  await page.goto('https://github.com/Gyeom/dev-notes/pulls');
  await page.waitForLoadState('networkidle');
  await page.screenshot({ path: `${outputDir}/03-pr-list.png` });

  // 4. PR #4 상세
  console.log('Capturing PR #4...');
  await page.goto('https://github.com/Gyeom/dev-notes/pull/4');
  await page.waitForLoadState('networkidle');
  await page.screenshot({ path: `${outputDir}/04-pr-detail.png`, fullPage: true });

  // 5. Actions 탭
  console.log('Capturing Actions...');
  await page.goto('https://github.com/Gyeom/dev-notes/actions');
  await page.waitForLoadState('networkidle');
  await page.screenshot({ path: `${outputDir}/05-actions-list.png` });

  // 6. 특정 워크플로우 실행 상세
  console.log('Capturing workflow run...');
  await page.goto('https://github.com/Gyeom/dev-notes/actions/runs/19780314599');
  await page.waitForLoadState('networkidle');
  await page.screenshot({ path: `${outputDir}/06-workflow-run.png` });

  // 7. 블로그 메인 페이지
  console.log('Capturing blog...');
  await page.goto('https://gyeom.github.io/dev-notes/');
  await page.waitForLoadState('networkidle');
  await page.screenshot({ path: `${outputDir}/07-blog-main.png` });

  await browser.close();
  console.log('Done! Screenshots saved to:', outputDir);
}

captureScreenshots().catch(console.error);
