// Direct port of Pake's macOS link-guard cases. It executes the exact script
// injected by Nimino's generated host and stubs only the explicit RPC edge.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const source = fs.readFileSync(path.join(__dirname, '..', 'macos_link_guard.js'), 'utf8');

function load(invoke = () => Promise.resolve({ id: 'popup-1' })) {
  const listeners = { click: [] };
  const originalCalls = [];
  const location = { href: 'https://example.com/app' };
  const window = {
    location,
    nimino: { invoke },
    open(...args) { originalCalls.push(args); return { native: true }; },
  };
  const context = {
    URL, Promise, setTimeout, clearTimeout, window, location,
    nimino: window.nimino,
    document: {
      baseURI: 'https://example.com/app',
      addEventListener(type, handler) { listeners[type].push(handler); },
    },
  };
  context.globalThis = context;
  vm.runInNewContext(`globalThis.__niminoLinkGuardConfig={newWindow:false,forceInternalNavigation:false,internalUrlRegex:'',appUrl:'https://example.com/app'};\n${source}`, context);
  return { window, location, originalCalls, listeners };
}

async function flush() { await Promise.resolve(); await Promise.resolve(); }

async function main() {
  {
    const page = load();
    const result = page.window.open('https://www.linkedin.com/login', '_blank', 'width=1200');
    assert.equal(result, page.window);
    assert.equal(page.location.href, 'https://www.linkedin.com/login');
    assert.deepEqual(page.originalCalls, []);
  }
  {
    const calls = [];
    const page = load((method, params) => { calls.push([method, params]); return Promise.resolve({ id: 'blank-1' }); });
    const popup = page.window.open('about:blank', 'login', 'width=1200,height=800');
    assert.equal(popup.closed, false);
    await flush();
    popup.location.href = 'https://appleid.apple.com/auth/authorize';
    await flush();
    assert.equal(JSON.stringify(calls), JSON.stringify([
      ['app.openPopup', { url: 'about:blank', name: 'login', specs: 'width=1200,height=800' }],
      ['app.navigatePopup', { id: 'blank-1', url: 'https://appleid.apple.com/auth/authorize' }],
    ]));
  }
  {
    const calls = [];
    const page = load((method, params) => { calls.push([method, params]); return Promise.resolve({ id: 'apple-1' }); });
    const popup = page.window.open('https://appleid.apple.com/auth/authorize', 'AppleAuthentication', 'width=1200');
    await flush();
    assert.equal(popup.closed, false);
    assert.equal(JSON.stringify(calls), JSON.stringify([[
      'app.openPopup', { url: 'https://appleid.apple.com/auth/authorize', name: 'AppleAuthentication', specs: 'width=1200' },
    ]]));
  }
  {
    const page = load(() => Promise.reject(new Error('blocked')));
    const popup = page.window.open('https://appleid.apple.com/auth/authorize', '_blank', 'width=1200');
    await flush();
    assert.equal(popup.closed, true);
    assert.equal(page.location.href, 'https://appleid.apple.com/auth/authorize');
  }
  {
    const page = load();
    page.window.open('javascript:void(0)', '_blank');
    assert.deepEqual(page.originalCalls, [['javascript:void(0)', '_blank', undefined]]);
    const anchor = { href: 'https://example.com/callback', target: '_blank', getAttribute: () => '/callback' };
    const event = { target: { closest: () => anchor }, preventDefault() {}, stopImmediatePropagation() {} };
    page.listeners.click[0](event);
    assert.equal(anchor.target, '_self');
  }
  process.stdout.write('macOS link guard contract passed\n');
}

main().catch((error) => { console.error(error.stack || error); process.exitCode = 1; });
