// NUI をヘッドレス Chromium で開いてスクリーンショットを撮る（ta-arcade の ui-shot.js と同じ方法。追加の部品なし）
// node ui-shot.js <URL> <出力フォルダ> "<手順>" [幅x高さ]
// 手順の例: "wait:600,shot:open,click:.chip[data-color='27'],wait:200,shot:red,key:ArrowDown,wait:400,shot:down"
const { spawn } = require('child_process');
const fs = require('fs'), path = require('path');
const [url, outDir, steps, size = '1920x1080'] = process.argv.slice(2);
const [W, H] = size.split('x').map(Number);
const SHELL = path.join(process.env.LOCALAPPDATA, 'ms-playwright/chromium_headless_shell-1148/chrome-win/headless_shell.exe');
const port = 9334;
const proc = spawn(SHELL, ['--headless', '--disable-gpu', `--remote-debugging-port=${port}`, `--window-size=${W},${H}`,
  '--allow-file-access-from-files', '--hide-scrollbars', 'about:blank'], { stdio: 'ignore' });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
(async () => {
  let ws;
  for (let i = 0; i < 50; i++) {
    try { const list = await (await fetch(`http://127.0.0.1:${port}/json`)).json(); const pg = list.find((t) => t.type === 'page'); if (pg) { ws = new WebSocket(pg.webSocketDebuggerUrl); break; } } catch (e) {}
    await sleep(200);
  }
  await new Promise((r) => ws.addEventListener('open', r));
  let id = 0; const pending = new Map();
  ws.addEventListener('message', (e) => { const m = JSON.parse(e.data); if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); } });
  const send = (method, params = {}) => new Promise((r) => { const i = ++id; pending.set(i, r); ws.send(JSON.stringify({ id: i, method, params })); });
  await send('Page.enable'); await send('Runtime.enable');
  await send('Emulation.setDeviceMetricsOverride', { width: W, height: H, deviceScaleFactor: 1, mobile: false });
  await send('Page.navigate', { url });
  await sleep(1000);
  fs.mkdirSync(outDir, { recursive: true });
  const evalJs = async (expr) => (await send('Runtime.evaluate', { expression: expr, returnByValue: true })).result.result.value;
  for (const st of steps.split(',')) {
    const [k, ...rest] = st.split(':'); const v = rest.join(':');
    if (k === 'wait') await sleep(+v);
    else if (k === 'click') console.log('click', v, await evalJs(`(() => { const el = document.querySelector(${JSON.stringify(v)}); if (!el) return false; el.click(); return true; })()`));
    else if (k === 'key') {
      const codes = { ArrowDown: 40, ArrowUp: 38, Escape: 27 };
      await send('Input.dispatchKeyEvent', { type: 'keyDown', key: v, code: v, windowsVirtualKeyCode: codes[v] || 0 });
      await send('Input.dispatchKeyEvent', { type: 'keyUp', key: v, code: v, windowsVirtualKeyCode: codes[v] || 0 });
    } else if (k === 'eval') console.log('eval', JSON.stringify(await evalJs(v)));
    else if (k === 'shot') {
      const r = await send('Page.captureScreenshot', { format: 'png' });
      fs.writeFileSync(path.join(outDir, v + '.png'), Buffer.from(r.result.data, 'base64')); console.log('shot', v);
    }
  }
  ws.close(); proc.kill();
})().catch((e) => { console.error(e); proc.kill(); process.exit(1); });
