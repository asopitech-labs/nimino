## macOS runtime regression coverage for Pake's find-shortcuts suite.
## This exercises Nimino's document-start injection in a real WKWebView rather
## than asserting only that the host menu contains the expected labels.

import std/[asyncfutures, strutils]

import nimino_core

var appPtr: pointer
var windowPtr: pointer
var disabledWindowPtr: pointer
var evaluationStarted: bool
var evaluationFinished: bool
var disabledEvaluationStarted: bool
var disabledEvaluationFinished: bool

proc finish() {.gcsafe.} =
  if evaluationFinished and disabledEvaluationFinished:
    ## The native navigation callback is delivered on AppKit's main thread.
    ## `App.quit` also closes user-provided RPC callbacks, which Nim cannot
    ## prove GC-safe even though this smoke owns no such callbacks.
    {.cast(gcsafe).}:
      doAssert cast[App](appPtr).quit().isOk

proc onEvaluation(completed: Future[CoreResultOf[string]]) {.gcsafe.} =
  doAssert not completed.failed
  let evaluated = completed.read()
  doAssert evaluated.isOk
  ## WKWebView returns the JSON string as a quoted JavaScript value.
  doAssert evaluated.value.contains("\\\"findApi\\\":true")
  doAssert evaluated.value.contains("\\\"findPanel\\\":true")
  doAssert evaluated.value.contains("\\\"shortcutHandled\\\":true")
  doAssert evaluated.value.contains("\\\"searchWorked\\\":true")
  doAssert evaluated.value.contains("\\\"trailingCommentInjected\\\":true")
  evaluationFinished = true
  finish()

proc onDisabledEvaluation(completed: Future[CoreResultOf[string]]) {.gcsafe.} =
  doAssert not completed.failed
  let evaluated = completed.read()
  doAssert evaluated.isOk
  doAssert evaluated.value.contains("\\\"findAbsent\\\":true")
  doAssert evaluated.value.contains("\\\"shortcutIgnored\\\":true")
  doAssert evaluated.value.contains("\\\"noPanel\\\":true")
  disabledEvaluationFinished = true
  finish()

proc onNavigation(url: string; succeeded: bool) {.gcsafe.} =
  doAssert succeeded
  if evaluationStarted:
    return
  evaluationStarted = true
  ## AppKit delivers this native callback on the main thread. Nim's async
  ## FFI completion path is conservatively unannotated, so narrow the proof
  ## boundary to this test's single main-thread evaluation request.
  {.cast(gcsafe).}:
    let evaluation = cast[Window](windowPtr).evalJavaScript("""
(() => {
  const event = new KeyboardEvent('keydown', {
    key: 'f', metaKey: true, bubbles: true, cancelable: true
  });
  document.dispatchEvent(event);
  const panel = document.querySelector('[role="search"][aria-label="Find in page"]');
  const searchWorked = window.nimino.find('Nimino Find Needle') === true;
  return JSON.stringify({
    findApi: typeof window.nimino?.find === 'function',
    findPanel: panel !== null && panel.hidden === false,
    shortcutHandled: event.defaultPrevented,
    searchWorked,
    trailingCommentInjected: window.niminoTrailingCommentInjected === true,
  });
})()
""")
    evaluation.addCallback(onEvaluation)

proc onDisabledNavigation(url: string; succeeded: bool) {.gcsafe.} =
  doAssert succeeded
  if disabledEvaluationStarted:
    return
  disabledEvaluationStarted = true
  {.cast(gcsafe).}:
    let evaluation = cast[Window](disabledWindowPtr).evalJavaScript("""
(() => {
  const event = new KeyboardEvent('keydown', {
    key: 'f', metaKey: true, bubbles: true, cancelable: true
  });
  document.dispatchEvent(event);
  return JSON.stringify({
    findAbsent: typeof window.nimino?.findPanel === 'undefined',
    shortcutIgnored: event.defaultPrevented === false,
    noPanel: document.querySelector('[role="search"][aria-label="Find in page"]') === null,
  });
})()
""")
    evaluation.addCallback(onDisabledEvaluation)

## This GUI smoke may be re-run while a previous failed process is still
## winding down, so it must not make an instance-lock collision look like a
## find-feature failure.
let created = newApp(AppOptions(id: "tech.asopi.nimino.macos-find-smoke",
  name: "Nimino macOS Find Smoke", multiInstance: true))
doAssert created.isOk, created.failure.detail
let app = created.value
appPtr = cast[pointer](app)
let window = app.newWindow(CoreWindowOptions(
  title: "Nimino macOS Find Smoke", width: 480, height: 280,
  enableFind: true, injectionEnabled: true, multiWindow: false,
  injectionJavaScript: @["globalThis.niminoTrailingCommentInjected=true;// source-map style trailing comment"]))
doAssert window.isOk, window.failure.detail
let appWindow = window.value
windowPtr = cast[pointer](appWindow)
doAssert appWindow.onNavigationCompleted(onNavigation).isOk
doAssert appWindow.loadHtml("""
<!doctype html><title>Nimino Find Smoke</title>
<main><p>Nimino Find Needle</p><p>Nimino Find Needle</p></main>
""").isOk
let disabledWindow = app.newWindow(CoreWindowOptions(
  title: "Nimino macOS Find Disabled", width: 360, height: 220,
  multiWindow: false))
doAssert disabledWindow.isOk, disabledWindow.failure.detail
let disabledAppWindow = disabledWindow.value
disabledWindowPtr = cast[pointer](disabledAppWindow)
doAssert disabledAppWindow.onNavigationCompleted(onDisabledNavigation).isOk
doAssert disabledAppWindow.loadHtml("""
<!doctype html><title>Nimino Find Disabled</title><main>No injected find panel</main>
""").isOk
doAssert app.run().isOk
doAssert evaluationStarted
doAssert evaluationFinished
doAssert disabledEvaluationStarted
doAssert disabledEvaluationFinished
echo "macOS find injection smoke passed"
