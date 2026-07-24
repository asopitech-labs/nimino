## Browser-facing compatibility helpers used by generated Nimino hosts.
##
## Keep these scripts separate from host startup so a real WKWebView smoke can
## exercise the exact source delivered to a packaged application.

import std/json

const
  MacosLinkGuardScript = staticRead("macos_link_guard.js")
  NonMacWebShortcutScript = staticRead("web_shortcuts.js")

proc macosWebCompatibilityScripts*(newWindow = false;
                                  forceInternalNavigation = false;
                                  internalUrlRegex = "";
                                  appUrl = ""): seq[string] =
  ## Pake's macOS bridge exposes Web Badging and Notification while delivery
  ## remains native.  The RPC names intentionally stay in Nimino's explicit
  ## allow-list; web content cannot reach arbitrary host operations.
  result.add("(() => { const invoke = (params) => globalThis.nimino && globalThis.nimino.invoke ? " &
    "globalThis.nimino.invoke('app.setDockBadge', params) : " &
    "Promise.reject(new Error('Nimino badge RPC is unavailable')); " &
    "const setBadge = (count) => { if (count == null) return invoke({label:'•'}); " &
    "const numeric=Number(count); if (!Number.isFinite(numeric)||numeric<0) return Promise.reject(new TypeError('badge count must be a non-negative number')); " &
    "const normalized=Math.floor(numeric); return invoke(normalized ? {count:normalized} : {label:''}); }; " &
    "const clearBadge = () => invoke({label:''}); " &
    "if (globalThis.navigator) { globalThis.navigator.setAppBadge = setBadge; " &
    "globalThis.navigator.clearAppBadge = clearBadge; } " &
    "globalThis.nimino = globalThis.nimino || {}; " &
    "globalThis.nimino.setDockBadge = setBadge; " &
    "globalThis.nimino.clearDockBadge = clearBadge; })();")
  result.add("(() => { document.addEventListener('nimino-notification', (event) => { " &
    "const detail = event.detail || {}; const banner = document.createElement('div'); " &
    "banner.setAttribute('role','status'); banner.textContent = detail.title ? " &
    "`${detail.title}: ${detail.body || ''}` : (detail.body || 'Notification'); " &
    "Object.assign(banner.style,{position:'fixed',right:'20px',top:'20px',zIndex:'2147483647'," &
    "padding:'12px 16px',borderRadius:'8px',background:'#222',color:'#fff'," &
    "font:'-apple-system,BlinkMacSystemFont,sans-serif',boxShadow:'0 4px 16px #0006'}); " &
    "banner.tabIndex=0; banner.style.cursor='pointer'; banner.addEventListener('click',() => " &
    "window.dispatchEvent(new CustomEvent('nimino-notification-activated',{detail:{id:detail.id}}))); " &
    "(document.body || document.documentElement).appendChild(banner); " &
    "setTimeout(() => banner.remove(), 5000); }); })();")
  result.add("(() => { const active = new Map(); let sequence = 0; " &
    "const syncBadge = () => { const n = active.size; if (navigator.setAppBadge) " &
    "navigator.setAppBadge(n || 0).catch(() => {}); }; " &
    "function NiminoNotification(title, options = {}) { if (!(this instanceof NiminoNotification)) " &
    "return new NiminoNotification(title, options); this.title = String(title || ''); " &
    "this.body = options && options.body != null ? String(options.body) : ''; " &
    "this.icon = ''; if (options && options.icon != null) { try { this.icon = new URL(String(options.icon),document.baseURI||location.href).href; } catch (_) {} } " &
    "this.tag = options && options.tag != null ? String(options.tag) : ''; this.onclick = null; " &
    "this.id = this.tag || ('nimino-notification-' + Date.now().toString(36) + '-' + (++sequence)); " &
    "active.set(this.id, this); syncBadge(); const invoke = globalThis.nimino && globalThis.nimino.invoke; " &
    "if (invoke) invoke('app.sendNotification', {id:this.id,title:this.title,body:this.body,icon:this.icon}).catch(() => {}); " &
    "} NiminoNotification.permission = 'granted'; " &
    "NiminoNotification.requestPermission = () => Promise.resolve('granted'); " &
    "NiminoNotification.prototype.close = function() { active.delete(this.id); syncBadge(); }; " &
    "globalThis.Notification = NiminoNotification; " &
    "globalThis.addEventListener('nimino-notification-activated', (event) => { " &
    "const n = active.get(event.detail && event.detail.id); if (!n) return; active.delete(n.id); syncBadge(); " &
    "if (typeof n.onclick === 'function') n.onclick.call(n, new Event('click')); }); })();")
  ## Pake guards links before site handlers run. The native navigation policy
  ## remains authoritative for every resulting navigation and popup redirect.
  let linkConfig = "{newWindow:" & (if newWindow: "true" else: "false") &
    ",forceInternalNavigation:" &
    (if forceInternalNavigation: "true" else: "false") &
    ",internalUrlRegex:" & $(%internalUrlRegex) & ",appUrl:" & $(%appUrl) & "}"
  result.add("globalThis.__niminoLinkGuardConfig=" & linkConfig & ";" &
    MacosLinkGuardScript)

proc nonMacWebShortcutScripts*(disabledWebShortcuts = false): seq[string] =
  ## Pake handles Ctrl+C/X/A/V and F11 in the page only on Windows/Linux.
  ## Clipboard fallback deliberately lets a native paste arrive first so rich
  ## formats, images, and files are never replaced by text-only clipboard data.
  result.add("globalThis.__niminoDisabledWebShortcuts=" &
    (if disabledWebShortcuts: "true;" else: "false;") &
    NonMacWebShortcutScript)
