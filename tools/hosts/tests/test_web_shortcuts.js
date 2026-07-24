// Direct port of Pake's event-clipboard-shortcuts and
// event-fullscreen-shortcuts unit coverage.  It executes the exact
// document-start script emitted by Nimino's generated host.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const source = fs.readFileSync(path.join(__dirname, '..', 'web_shortcuts.js'), 'utf8');

function element(tagName = 'div', values = {}) {
  return {
    tagName: tagName.toUpperCase(), style: {}, children: [], isContentEditable: false,
    disabled: false, readOnly: false, type: 'text', value: '',
    addEventListener() {}, dispatchEvent() {}, appendChild(child) { this.children.push(child); return child; },
    ...values,
  };
}

function key(key, values = {}) {
  return {
    key, ctrlKey: true, metaKey: false, altKey: false, shiftKey: false,
    isTrusted: true, repeat: false, prevented: false, stopped: false,
    preventDefault() { this.prevented = true; },
    stopImmediatePropagation() { this.stopped = true; },
    ...values,
  };
}

function load({ active = element('body'), selection = '', clipboard = 'clipboard text',
  rejectClipboard = false, disabledWebShortcuts = false } = {}) {
  const listeners = { keydown: [], keyup: [], paste: [] };
  const calls = [];
  const invokes = [];
  const reads = [];
  const body = element('body');
  const selectionState = { removeAllRanges() {}, addRange() {} };
  const context = {
    console, Date, Promise, setTimeout, clearTimeout,
    Event: class Event { constructor(type, init) { this.type = type; Object.assign(this, init); } },
    navigator: { clipboard: { readText() { reads.push(true); return rejectClipboard ?
      Promise.reject(new Error('denied')) : Promise.resolve(clipboard); } } },
    window: { getSelection: () => ({ ...selectionState, toString: () => selection }),
      nimino: { invoke(method, params) { invokes.push([method, params]); return Promise.resolve(); } } },
    document: {
      activeElement: active, body,
      addEventListener(type, handler) { listeners[type].push(handler); },
      execCommand(command, showUI, value) { calls.push([command, showUI, value]); return true; },
      createRange: () => ({ selectNodeContents() {} }),
    },
  };
  context.globalThis = context;
  vm.runInNewContext(`globalThis.__niminoDisabledWebShortcuts=${disabledWebShortcuts};\n${source}`, context);
  const fire = (type, event) => listeners[type].forEach((handler) => handler(event));
  return { context, calls, invokes, reads, fire };
}

async function flush() { await Promise.resolve(); await Promise.resolve(); }

const tests = [];
function test(name, body) { tests.push([name, body]); }

test('copies selected page text', () => {
  const page = load({ selection: 'selected text' });
  const event = key('c'); page.fire('keydown', event);
  assert.deepEqual(page.calls, [['copy', undefined, undefined]]);
  assert.equal(event.prevented, true);
});

test('cuts and selects editable text', () => {
  const input = element('input', { selectCalled: false, select() { this.selectCalled = true; } });
  const page = load({ active: input });
  const cut = key('x'); const all = key('a');
  page.fire('keydown', cut); page.fire('keydown', all);
  assert.deepEqual(page.calls, [['cut', undefined, undefined]]);
  assert.equal(input.selectCalled, true);
  assert.equal(cut.prevented && all.prevented, true);
});

test('preserves rich native paste data', async () => {
  const editor = element('div', { isContentEditable: true });
  const page = load({ active: editor });
  page.fire('keydown', key('v'));
  page.fire('paste', { clipboardData: { types: ['Files', 'image/png'], getData: () => '' },
    preventDefault() { throw new Error('native paste must not be blocked'); },
    stopImmediatePropagation() { throw new Error('native paste must not be blocked'); } });
  page.fire('keyup', key('v')); await flush();
  assert.deepEqual(page.reads, []); assert.deepEqual(page.calls, []);
});

test('pastes plain text only when explicitly requested', () => {
  const input = element('input'); const page = load({ active: input });
  page.context.nimino.pasteAsPlainText();
  const event = { clipboardData: { getData: () => 'plain text' }, prevented: false, stopped: false,
    preventDefault() { this.prevented = true; }, stopImmediatePropagation() { this.stopped = true; } };
  page.fire('paste', event);
  assert.equal(event.prevented && event.stopped, true);
  assert.deepEqual(page.calls, [['paste', undefined, undefined], ['insertText', false, 'plain text']]);
});

test('uses text fallback only when native paste does not arrive', async () => {
  const input = element('input'); const page = load({ active: input, clipboard: 'pasted text' });
  const down = key('v'); page.fire('keydown', down); page.fire('keyup', key('v')); await flush();
  assert.equal(down.prevented, false); assert.equal(page.reads.length, 1);
  assert.deepEqual(page.calls, [['insertText', false, 'pasted text']]);
});

test('does not rearm fallback after native paste during key repeat', async () => {
  const input = element('input'); const page = load({ active: input });
  page.fire('keydown', key('v'));
  page.fire('paste', { clipboardData: { types: ['image/png'], getData: () => '' }, preventDefault() {}, stopImmediatePropagation() {} });
  page.fire('keydown', key('v', { repeat: true })); page.fire('keyup', key('v')); await flush();
  assert.deepEqual(page.reads, []); assert.deepEqual(page.calls, []);
});

test('expires a stale fallback and ignores a synthetic keyup', async () => {
  const input = element('input'); const page = load({ active: input });
  page.fire('keydown', key('v'));
  page.context.Date = { now: () => Date.now() + 10_000 };
  page.fire('keyup', key('v')); await flush();
  assert.deepEqual(page.reads, []);
  page.context.Date = Date;
  page.fire('keydown', key('v'));
  page.fire('keyup', key('v', { isTrusted: false })); await flush();
  assert.deepEqual(page.reads, []);
});

test('ignores synthetic shortcuts and non-text inputs', async () => {
  const checkbox = element('input', { type: 'checkbox' }); const page = load({ active: checkbox });
  const synthetic = key('v', { isTrusted: false }); page.fire('keydown', synthetic); page.fire('keyup', synthetic);
  page.fire('keydown', key('v')); page.fire('keyup', key('v')); await flush();
  assert.deepEqual(page.reads, []); assert.equal(synthetic.prevented, false);
});

test('does not paste when clipboard access is denied', async () => {
  const input = element('input'); const page = load({ active: input, rejectClipboard: true });
  page.fire('keydown', key('v')); page.fire('keyup', key('v')); await flush();
  assert.equal(page.reads.length, 1); assert.deepEqual(page.calls, []);
});

test('toggles fullscreen on a trusted non-repeated F11', async () => {
  const page = load(); const event = key('F11', { ctrlKey: false }); page.fire('keydown', event); await flush();
  assert.equal(event.prevented && event.stopped, true);
  assert.deepEqual(page.invokes, [['app.toggleFullscreen', {}]]);
});

test('does not claim synthetic, repeated, Alt+Enter, or disabled F11', async () => {
  const page = load();
  page.fire('keydown', key('F11', { ctrlKey: false, isTrusted: false }));
  page.fire('keydown', key('F11', { ctrlKey: false, repeat: true }));
  page.fire('keydown', key('Enter', { ctrlKey: false, altKey: true }));
  const disabled = load({ disabledWebShortcuts: true });
  disabled.fire('keydown', key('F11', { ctrlKey: false })); await flush();
  assert.deepEqual(page.invokes, []); assert.deepEqual(disabled.invokes, []);
});

(async () => {
  for (const [name, body] of tests) {
    await body();
    process.stdout.write(`ok - ${name}\n`);
  }
})().catch((error) => { console.error(error.stack || error); process.exitCode = 1; });
