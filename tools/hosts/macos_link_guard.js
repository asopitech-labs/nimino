(() => {
  const config = globalThis.__niminoLinkGuardConfig || {};
  const bypass = (value) => {
    const href = String(value || '').trim().toLowerCase();
    return href.startsWith('javascript:') || href.startsWith('#');
  };
  const documentBase = () => document.baseURI || location.href;
  const absolute = (value) => new URL(String(value || ''), documentBase()).href;
  const isAuth = (value) => {
    try {
      const parsed = new URL(value, documentBase());
      const host = parsed.hostname.toLowerCase();
      const path = parsed.pathname.toLowerCase();
      return host === 'accounts.google.com' || host.endsWith('.accounts.google.com') ||
        host === 'googleusercontent.com' || host.endsWith('.googleusercontent.com') ||
        host === 'login.microsoftonline.com' || host.endsWith('.microsoftonline.com') ||
        host === 'login.live.com' || host.endsWith('.okta.com') ||
        host.endsWith('.auth0.com') || host.endsWith('.onelogin.com') ||
        host === 'appleid.apple.com' ||
        ((host === 'www.linkedin.com' || host === 'linkedin.com') &&
          (path === '/login' || path.startsWith('/login/'))) ||
        (host === 'github.com' && (path === '/login' || path.startsWith('/login/'))) ||
        ((host === 'facebook.com' || host.endsWith('.facebook.com')) && path.includes('/dialog')) ||
        ((host === 'twitter.com' || host.endsWith('.twitter.com') ||
          host === 'x.com' || host.endsWith('.x.com')) && path.startsWith('/oauth')) ||
        path === '/adfs/ls' || path.startsWith('/adfs/ls/');
    } catch (_) { return false; }
  };
  const isInternal = (value) => {
    if (config.forceInternalNavigation) return true;
    try {
      if (config.internalUrlRegex && new RegExp(config.internalUrlRegex).test(value)) return true;
      return new URL(value).origin === new URL(config.appUrl || documentBase()).origin;
    } catch (_) { return false; }
  };
  const current = (url) => { location.href = url; return window; };
  const invoke = (method, params) => {
    const call = globalThis.nimino?.invoke;
    return typeof call === 'function' ? call(method, params) : Promise.reject(new Error('Nimino RPC unavailable'));
  };

  const openNativePopup = (url, name, specs) => {
    const state = { id: '', href: url, closed: false, ready: null };
    const proxy = { focus() {}, close() {
      if (state.closed) return;
      state.closed = true;
      if (state.id) invoke('app.closePopup', { id: state.id }).catch(() => {});
    } };
    Object.defineProperty(proxy, 'closed', { get: () => state.closed });
    const popupLocation = {};
    Object.defineProperty(popupLocation, 'href', {
      get: () => state.href,
      set: (value) => {
        try { state.href = absolute(value); } catch (_) { return; }
        state.ready = state.ready.then(() => invoke('app.navigatePopup', { id: state.id, url: state.href }));
        state.ready.catch(() => { if (!state.closed) { state.closed = true; current(state.href); } });
      },
    });
    proxy.location = popupLocation;
    state.ready = invoke('app.openPopup', { url, name: String(name || ''), specs: String(specs || '') })
      .then((result) => { if (!result || typeof result.id !== 'string') throw new Error('popup id missing'); state.id = result.id; return result; })
      .catch(() => { state.closed = true; if (url.toLowerCase() !== 'about:blank') current(url); });
    return proxy;
  };

  document.addEventListener('click', (event) => {
    const anchor = event.target && typeof event.target.closest === 'function' ? event.target.closest('a') : null;
    if (!anchor || !anchor.href || bypass(anchor.getAttribute('href') || '')) return;
    let url; try { url = absolute(anchor.href); } catch (_) { return; }
    if (isAuth(url) && !config.newWindow) {
      event.preventDefault(); event.stopImmediatePropagation(); current(url); return;
    }
    if (anchor.target === '_blank') {
      if (config.forceInternalNavigation) { event.preventDefault(); event.stopImmediatePropagation(); current(url); }
      else if (isInternal(url) && !config.newWindow) anchor.target = '_self';
    }
  }, true);

  const originalOpen = window.open;
  window.open = function(url, name, specs) {
    if (bypass(url)) return originalOpen.call(window, url, name, specs);
    let target; try { target = absolute(url); } catch (_) { return originalOpen.call(window, url, name, specs); }
    const applePopup = name === 'AppleAuthentication' || (() => {
      try { return new URL(target).hostname.toLowerCase() === 'appleid.apple.com'; } catch (_) { return false; }
    })();
    if (target.toLowerCase() === 'about:blank' || applePopup) return openNativePopup(target, name, specs);
    if (isAuth(target)) return current(target);
    return originalOpen.call(window, target, name, specs);
  };
})();
