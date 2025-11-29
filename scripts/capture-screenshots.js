#!/usr/bin/env node
/**
 * 범용 스크린샷 캡처 스크립트
 *
 * 사용법:
 *   node scripts/capture-screenshots.js <config.json>
 *   node scripts/capture-screenshots.js --url <URL> --output <filename>
 *
 * config.json 예시:
 * {
 *   "outputDir": "./static/images/screenshots",
 *   "viewport": { "width": 1280, "height": 800 },
 *   "pages": [
 *     { "url": "https://example.com", "filename": "example.png" },
 *     { "url": "https://example.com/page", "filename": "page.png", "fullPage": true }
 *   ]
 * }
 */

const { chromium } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

const DEFAULT_CONFIG = {
  outputDir: './static/images',
  viewport: { width: 1280, height: 800 },
  deviceScaleFactor: 2,
};

async function captureScreenshot(page, config, outputDir) {
  const { url, filename, fullPage = false, waitFor, selector } = config;

  console.log(`Capturing: ${url}`);
  await page.goto(url);
  await page.waitForLoadState('networkidle');

  if (waitFor) {
    await page.waitForTimeout(waitFor);
  }

  const outputPath = path.join(outputDir, filename);

  if (selector) {
    const element = await page.$(selector);
    if (element) {
      await element.screenshot({ path: outputPath });
    } else {
      console.warn(`Selector not found: ${selector}`);
      await page.screenshot({ path: outputPath, fullPage });
    }
  } else {
    await page.screenshot({ path: outputPath, fullPage });
  }

  console.log(`  Saved: ${outputPath}`);
}

async function main() {
  const args = process.argv.slice(2);

  let config;

  // 명령줄 인자 파싱
  if (args.includes('--url')) {
    const urlIndex = args.indexOf('--url');
    const outputIndex = args.indexOf('--output');

    const url = args[urlIndex + 1];
    const filename = outputIndex !== -1 ? args[outputIndex + 1] : 'screenshot.png';

    config = {
      ...DEFAULT_CONFIG,
      pages: [{ url, filename }],
    };
  } else if (args[0] && fs.existsSync(args[0])) {
    const fileConfig = JSON.parse(fs.readFileSync(args[0], 'utf-8'));
    config = { ...DEFAULT_CONFIG, ...fileConfig };
  } else {
    console.log(`Usage:
  node capture-screenshots.js <config.json>
  node capture-screenshots.js --url <URL> --output <filename>

Options:
  --url     URL to capture
  --output  Output filename (default: screenshot.png)

Config file format:
{
  "outputDir": "./static/images",
  "viewport": { "width": 1280, "height": 800 },
  "pages": [
    { "url": "https://example.com", "filename": "home.png" },
    { "url": "https://example.com/about", "filename": "about.png", "fullPage": true }
  ]
}`);
    process.exit(1);
  }

  // 출력 디렉토리 생성
  if (!fs.existsSync(config.outputDir)) {
    fs.mkdirSync(config.outputDir, { recursive: true });
  }

  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({
    viewport: config.viewport,
    deviceScaleFactor: config.deviceScaleFactor || 2,
  });
  const page = await context.newPage();

  try {
    for (const pageConfig of config.pages) {
      await captureScreenshot(page, pageConfig, config.outputDir);
    }
  } finally {
    await browser.close();
  }

  console.log('Done!');
}

main().catch(console.error);
