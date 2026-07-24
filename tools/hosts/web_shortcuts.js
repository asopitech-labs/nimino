(() => {
  const nonTextInputTypes = new Set([
    'button', 'checkbox', 'color', 'file', 'hidden', 'image', 'radio',
    'range', 'reset', 'submit',
  ]);
  let pasteFallbackTarget;
  let pasteFallbackArmedAt = 0;
  let pasteAsPlainTextPending = false;
  const pasteFallbackTtlMs = 5000;

  const isEditable = (element) => Boolean(element) &&
    (element.tagName === 'INPUT' || element.tagName === 'TEXTAREA' ||
      element.isContentEditable);
  const isTextInput = (element) => element?.tagName === 'INPUT' &&
    !nonTextInputTypes.has(String(element.type || 'text').toLowerCase());
  const canPaste = (element) => isEditable(element) &&
    (element.tagName !== 'INPUT' || isTextInput(element)) &&
    element.disabled !== true && element.readOnly !== true;

  const insertText = (element, text) => {
    if (!text) return false;
    if (document.execCommand('insertText', false, text)) return true;
    if (element && (isTextInput(element) || element.tagName === 'TEXTAREA') &&
        typeof element.setRangeText === 'function') {
      const length = typeof element.value === 'string' ? element.value.length : 0;
      const start = typeof element.selectionStart === 'number' ?
        element.selectionStart : length;
      const end = typeof element.selectionEnd === 'number' ?
        element.selectionEnd : start;
      element.setRangeText(text, start, end, 'end');
      element.dispatchEvent?.(new Event('input', { bubbles: true }));
      return true;
    }
    return false;
  };

  const selectEditable = (element) => {
    if (typeof element?.select === 'function') {
      element.select();
      return true;
    }
    if (element?.isContentEditable) {
      const range = document.createRange();
      range.selectNodeContents(element);
      const selection = window.getSelection?.();
      if (!selection) return false;
      selection.removeAllRanges();
      selection.addRange(range);
      return true;
    }
    return false;
  };

  globalThis.nimino = globalThis.nimino || {};
  globalThis.nimino.pasteAsPlainText = () => {
    pasteAsPlainTextPending = true;
    document.execCommand('paste');
    setTimeout(() => { pasteAsPlainTextPending = false; }, 100);
  };

  document.addEventListener('keydown', (event) => {
    if (event.isTrusted !== true || !event.ctrlKey || event.metaKey ||
        event.altKey || event.shiftKey) return;
    const key = String(event.key || '').toLowerCase();
    const active = document.activeElement;
    if (key === 'c' && (isEditable(active) || Boolean(window.getSelection?.()?.toString()))) {
      document.execCommand('copy');
      event.preventDefault();
      return;
    }
    if (key === 'x' && isEditable(active)) {
      document.execCommand('cut');
      event.preventDefault();
      return;
    }
    if (key === 'v' && canPaste(active)) {
      if (!event.repeat) {
        pasteFallbackTarget = active;
        pasteFallbackArmedAt = Date.now();
      } else if (pasteFallbackTarget === active) {
        pasteFallbackArmedAt = Date.now();
      }
      return;
    }
    if (key === 'a' && isEditable(active) && selectEditable(active)) {
      event.preventDefault();
    }
  }, true);

  document.addEventListener('keyup', (event) => {
    if (event.isTrusted !== true || String(event.key || '').toLowerCase() !== 'v') return;
    const active = pasteFallbackTarget;
    const armedAt = pasteFallbackArmedAt;
    pasteFallbackTarget = undefined;
    if (!active || Date.now() - armedAt > pasteFallbackTtlMs ||
        document.activeElement !== active || !canPaste(active)) return;
    const readText = navigator.clipboard?.readText;
    if (typeof readText === 'function') {
      readText.call(navigator.clipboard).then((text) => insertText(active, text)).catch(() => {});
    }
  }, true);

  document.addEventListener('paste', (event) => {
    pasteFallbackTarget = undefined;
    if (!pasteAsPlainTextPending) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    const text = event.clipboardData?.getData('text/plain') || '';
    if (text) document.execCommand('insertText', false, text);
  }, true);

  if (!globalThis.__niminoDisabledWebShortcuts) {
    document.addEventListener('keydown', (event) => {
      if (event.isTrusted !== true || event.repeat || event.key !== 'F11') return;
      const invoke = globalThis.nimino?.invoke;
      if (typeof invoke !== 'function') return;
      event.preventDefault();
      event.stopImmediatePropagation();
      Promise.resolve(invoke('app.toggleFullscreen', {})).catch(() => {});
    }, true);
  }
})();
