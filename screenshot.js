const puppeteer = require('puppeteer');
const path = require('path');

(async () => {
  const browser = await puppeteer.launch({ headless: 'new' });
  const page = await browser.newPage();
  await page.setViewport({ width: 1200, height: 1800 });
  
  const filePath = 'file:///' + path.resolve('G:/pub/htu.html').replace(/\\/g, '/');
  console.log('Loading:', filePath);
  
  await page.goto(filePath, { waitUntil: 'networkidle0' });
  await page.screenshot({ path: 'G:/pub/htu-screenshot.png', fullPage: true });
  
  console.log('Screenshot saved to htu-screenshot.png');
  await browser.close();
})();
