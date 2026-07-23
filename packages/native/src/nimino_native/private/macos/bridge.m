#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import <UserNotifications/UserNotifications.h>
#import <Network/Network.h>
#import <Security/Security.h>
#import <dispatch/dispatch.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <CommonCrypto/CommonDigest.h>

typedef void (*MacIdleCallback)(void *);
typedef int (*MacCloseCallback)(void *);
typedef void (*MacClosedCallback)(void *);
typedef void (*MacResizeCallback)(void *, int, int);
typedef void (*MacMoveCallback)(void *, int, int);
typedef void (*MacFileDropCallback)(void *, const char *);
typedef void (*MacMessageCallback)(void *, const char *);
typedef int (*MacBoolStringCallback)(void *, const char *);
typedef int (*MacNewWindowCallback)(void *, const char *, int, int, int, int, int, int, int, int);
typedef void (*MacNavigationCallback)(void *, const char *, int);
typedef void (*MacErrorCallback)(void *, const char *, const char *);
typedef void (*MacEvalCallback)(void *, void *, const char *, int, const char *);
typedef void (*MacClearCallback)(void *, void *, int);
typedef void (*MacCookieCallback)(void *, void *, const char *, const char *,
                                  const char *, const char *, int, int, int64_t);
typedef void (*MacCookiesDoneCallback)(void *, void *, int);
typedef void (*MacMenuCallback)(void *, unsigned int);
typedef void (*MacSchemeCallback)(void *, void *, const char *, const char *, const char *);
typedef void (*MacNotificationCallback)(void *, const char *);
typedef void (*MacDeepLinkCallback)(void *, const char *);
typedef void (*MacReopenCallback)(void *);
typedef int (*MacPermissionCallback)(void *, const char *, const char *);
typedef int (*MacDownloadStartingCallback)(void *, const char *);
typedef const char *(*MacDownloadPathCallback)(void *, const char *);
typedef void (*MacDownloadEventCallback)(void *, const char *, int, double);

typedef struct MacAppContext MacAppContext;
typedef struct MacWindowContext MacWindowContext;
typedef struct MacViewContext MacViewContext;

@interface NiminoTimerTarget : NSObject
@property(nonatomic, assign) MacAppContext *context;
@end

@interface NiminoWindowDelegate : NSObject <NSWindowDelegate>
@property(nonatomic, assign) MacWindowContext *context;
@end

@interface NiminoWebViewDelegate : NSObject <WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, WKDownloadDelegate>
@property(nonatomic, assign) MacViewContext *context;
@property(nonatomic, strong) NSHashTable *observedDownloads;
- (void)removeProgressObserverFromDownload:(WKDownload *)download;
@end

@interface NiminoDropView : NSView
@property(nonatomic, assign) MacWindowContext *context;
@end

@interface NiminoMenuTarget : NSObject
@property(nonatomic, assign) MacAppContext *context;
@property(nonatomic, assign) BOOL tray;
- (void)activateButton:(id)sender;
@end

@interface NiminoNotificationDelegate : NSObject <UNUserNotificationCenterDelegate>
@property(nonatomic, assign) MacAppContext *context;
@end

@interface NiminoApplicationDelegate : NSObject <NSApplicationDelegate>
@property(nonatomic, assign) MacAppContext *context;
@end

@interface NiminoSchemeHandler : NSObject <WKURLSchemeHandler>
@property(nonatomic, assign) MacAppContext *context;
@end

struct MacAppContext {
  void *userData;
  NSApplication *application;
  NSTimer *timer;
  NiminoTimerTarget *timerTarget;
  NSMenu *menu;
  NiminoMenuTarget *menuTarget;
  NSStatusItem *statusItem;
  NiminoMenuTarget *trayTarget;
  NiminoNotificationDelegate *notificationDelegate;
  NiminoApplicationDelegate *applicationDelegate;
  NSMutableArray *pendingDeepLinks;
  NSMutableSet *stoppedSchemeTasks;
  MacWindowContext *windows;
  MacMenuCallback menuCallback;
  MacMenuCallback trayCallback;
  MacIdleCallback shortcutCallback;
  id shortcutMonitor;
  id localShortcutMonitor;
  NSString *shortcutKey;
  NSUInteger shortcutModifiers;
  NSString *scheme;
  NiminoSchemeHandler *schemeHandler;
  MacSchemeCallback schemeCallback;
  MacNotificationCallback notificationCallback;
  MacDeepLinkCallback deepLinkCallback;
  MacReopenCallback reopenCallback;
};

struct MacWindowContext {
  void *userData;
  MacAppContext *app;
  NSWindow *window;
  NiminoWindowDelegate *delegate;
  NiminoDropView *dropView;
  MacViewContext *views;
  MacWindowContext *next;
  MacCloseCallback closeCallback;
  MacClosedCallback closedCallback;
  MacResizeCallback resizeCallback;
  MacMoveCallback moveCallback;
  MacFileDropCallback fileDropCallback;
};

struct MacViewContext {
  void *userData;
  MacWindowContext *window;
  int pendingCallbacks;
  BOOL disposed;
  WKWebView *webView;
  NiminoWebViewDelegate *delegate;
  MacViewContext *next;
  MacMessageCallback messageCallback;
  MacErrorCallback errorCallback;
  MacNewWindowCallback newWindowCallback;
  MacBoolStringCallback navigationStartingCallback;
  MacNavigationCallback navigationCompletedCallback;
  MacEvalCallback evalCallback;
  MacPermissionCallback permissionCallback;
  MacDownloadStartingCallback downloadStartingCallback;
  MacDownloadPathCallback downloadPathCallback;
  MacDownloadEventCallback downloadEventCallback;
  BOOL ignoreCertificateErrors;
};

void nimino_macos_window_dispose(void *opaque);

static void macViewRetainCallback(MacViewContext *context) {
  if (context) context->pendingCallbacks++;
}

static void macViewReleaseCallback(MacViewContext *context) {
  if (!context) return;
  if (context->pendingCallbacks > 0) context->pendingCallbacks--;
  if (context->disposed && context->pendingCallbacks == 0) free(context);
}

static void macViewUnlink(MacViewContext *context) {
  if (!context || !context->window) return;
  MacViewContext **cursor = &context->window->views;
  while (*cursor) {
    if (*cursor == context) {
      *cursor = context->next;
      context->window = NULL;
      return;
    }
    cursor = &(*cursor)->next;
  }
}

static const char *niminoString(NSString *value) {
  return value ? value.UTF8String : "";
}

static NSString *niminoJSONDescription(id value) {
  if (!value) return @"";
  NSError *error = nil;
  NSData *data = [NSJSONSerialization dataWithJSONObject:@[value] options:0 error:&error];
  if (!data || error) return [value description];
  NSString *json = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
  if (json.length < 2) return json ?: @"";
  return [json substringWithRange:NSMakeRange(1, json.length - 2)];
}

static BOOL niminoCookieMatchesURL(NSHTTPCookie *cookie, NSURL *url) {
  if (!cookie || !url || !url.host) return NO;
  NSString *host = url.host.lowercaseString;
  NSString *domain = cookie.domain.lowercaseString;
  while ([domain hasPrefix:@"."]) domain = [domain substringFromIndex:1];
  if (domain.length == 0) return NO;
  BOOL domainMatches = [host isEqualToString:domain] ||
    [host hasSuffix:[@"." stringByAppendingString:domain]];
  if (!domainMatches) return NO;
  if (cookie.isSecure && ![url.scheme.lowercaseString isEqualToString:@"https"]) return NO;

  NSString *requestPath = url.path.length > 0 ? url.path : @"/";
  NSString *cookiePath = cookie.path.length > 0 ? cookie.path : @"/";
  if (![requestPath hasPrefix:cookiePath]) return NO;
  if ([requestPath isEqualToString:cookiePath] || [cookiePath hasSuffix:@"/"]) return YES;
  return requestPath.length > cookiePath.length &&
    [requestPath characterAtIndex:cookiePath.length] == '/';
}

@implementation NiminoTimerTarget
- (void)tick:(NSTimer *)timer {
  (void)timer;
  if (self.context && self.context->userData) {
    MacIdleCallback callback = (MacIdleCallback)self.context->timerTarget;
    (void)callback;
  }
}
@end

/* The timer target stores only the context.  The callback is held in the
 * context's userData-independent field below to keep Objective-C objects out
 * of the Nim-facing ABI. */
static MacIdleCallback g_idleCallback = NULL;

@implementation NiminoWindowDelegate
- (BOOL)windowShouldClose:(NSWindow *)window {
  (void)window;
  if (!self.context || !self.context->closeCallback) return YES;
  return self.context->closeCallback(self.context->userData) ? NO : YES;
}
- (void)windowWillClose:(NSNotification *)notification {
  (void)notification;
  if (self.context && self.context->closedCallback)
    self.context->closedCallback(self.context->userData);
}
- (void)windowDidResize:(NSNotification *)notification {
  (void)notification;
  if (!self.context || !self.context->resizeCallback || !self.context->window) return;
  NSRect frame = self.context->window.contentView.bounds;
  self.context->resizeCallback(self.context->userData, (int)frame.size.width,
                               (int)frame.size.height);
}
- (void)windowDidMove:(NSNotification *)notification {
  (void)notification;
  if (!self.context || !self.context->moveCallback || !self.context->window) return;
  NSPoint origin = self.context->window.frame.origin;
  self.context->moveCallback(self.context->userData, (int)origin.x, (int)origin.y);
}
@end

@implementation NiminoDropView
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
  (void)sender;
  return self.context && self.context->fileDropCallback ? NSDragOperationCopy : NSDragOperationNone;
}
- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
  if (!self.context || !self.context->fileDropCallback) return NO;
  NSPasteboard *pasteboard = sender.draggingPasteboard;
  NSArray *urls = [pasteboard readObjectsForClasses:@[[NSURL class]]
                                               options:@{NSPasteboardURLReadingFileURLsOnlyKey:@YES}];
  for (NSURL *url in urls) {
    if (url.isFileURL) self.context->fileDropCallback(self.context->userData, url.path.UTF8String);
  }
  return urls.count > 0;
}
@end

@implementation NiminoMenuTarget
- (void)activate:(NSMenuItem *)item {
  if (self.tray && self.context && self.context->trayCallback)
    self.context->trayCallback(self.context->userData, (unsigned int)item.tag);
  else if (self.context && self.context->menuCallback)
    self.context->menuCallback(self.context->userData, (unsigned int)item.tag);
}
- (void)activateButton:(id)sender {
  (void)sender;
  if (self.tray && self.context && self.context->trayCallback)
    self.context->trayCallback(self.context->userData, 0);
}
@end

@implementation NiminoNotificationDelegate
- (void)userNotificationCenter:(UNUserNotificationCenter *)center
       willPresentNotification:(UNNotification *)notification
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions options))completionHandler {
  (void)center; (void)notification;
  if (completionHandler)
    completionHandler(UNNotificationPresentationOptionBanner |
                      UNNotificationPresentationOptionSound);
}
- (void)userNotificationCenter:(UNUserNotificationCenter *)center
 didReceiveNotificationResponse:(UNNotificationResponse *)response
          withCompletionHandler:(void (^)(void))completionHandler {
  (void)center;
  if (self.context && self.context->notificationCallback)
    self.context->notificationCallback(self.context->userData,
      niminoString(response.notification.request.identifier));
  if (completionHandler) completionHandler();
}
@end

static void niminoLogNotificationFailure(const char *operation, NSError *error) {
  fprintf(stderr, "nimino macOS notification unavailable (%s)",
          operation ? operation : "unknown");
  if (error && error.localizedDescription.UTF8String)
    fprintf(stderr, ": %s", error.localizedDescription.UTF8String);
  fprintf(stderr,
          ". An unsigned or Ad-hoc local bundle may launch but can be rejected by "
          "macOS UserNotifications; use an Apple-issued development identity for "
          "notification testing or provide an in-app fallback.\n");
}

static BOOL niminoHasAppleIssuedSigning(void) {
  SecCodeRef code = NULL;
  CFDictionaryRef information = NULL;
  if (SecCodeCopySelf(kSecCSDefaultFlags, &code) != errSecSuccess || !code)
    return NO;
  OSStatus status = SecCodeCopySigningInformation(code, kSecCSSigningInformation, &information);
  BOOL result = NO;
  if (status == errSecSuccess && information) {
    CFStringRef team = (CFStringRef)CFDictionaryGetValue(information, kSecCodeInfoTeamIdentifier);
    result = team && CFGetTypeID(team) == CFStringGetTypeID() && CFStringGetLength(team) > 0;
  }
  if (information) CFRelease(information);
  CFRelease(code);
  return result;
}

@implementation NiminoApplicationDelegate
- (void)application:(NSApplication *)application openURLs:(NSArray<NSURL *> *)urls {
  (void)application;
  if (!self.context) return;
  for (NSURL *url in urls) {
    if (url.absoluteString.length == 0) continue;
    if (self.context->deepLinkCallback)
      self.context->deepLinkCallback(self.context->userData, niminoString(url.absoluteString));
    else
      [self.context->pendingDeepLinks addObject:url.absoluteString];
  }
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)application
                    hasVisibleWindows:(BOOL)flag {
  (void)application;
  (void)flag;
  if (self.context && self.context->reopenCallback)
    self.context->reopenCallback(self.context->userData);
  return YES;
}
@end

@implementation NiminoSchemeHandler
- (void)webView:(WKWebView *)webView startURLSchemeTask:(id<WKURLSchemeTask>)task {
  (void)webView;
  if (!self.context || !self.context->schemeCallback) {
    [task didFailWithError:[NSError errorWithDomain:@"NiminoScheme" code:1 userInfo:nil]];
    return;
  }
  NSURLRequest *request = task.request;
  NSString *url = request.URL.absoluteString ?: @"";
  NSString *method = request.HTTPMethod ?: @"GET";
  NSString *path = request.URL.path ?: @"/";
  [self.context->stoppedSchemeTasks removeObject:task];
  self.context->schemeCallback(self.context->userData, task,
                               method.UTF8String, url.UTF8String, path.UTF8String);
}
- (void)webView:(WKWebView *)webView stopURLSchemeTask:(id<WKURLSchemeTask>)task {
  (void)webView;
  if (self.context && task)
    [self.context->stoppedSchemeTasks addObject:task];
}
@end

@implementation NiminoWebViewDelegate
- (void)userContentController:(WKUserContentController *)controller
      didReceiveScriptMessage:(WKScriptMessage *)message {
  (void)controller;
  if (!self.context || !self.context->messageCallback) return;
  if ([message.body isKindOfClass:[NSString class]]) {
    MacMessageCallback callback = self.context->messageCallback;
    void *userData = self.context->userData;
    NSString *body = [message.body copy];
    dispatch_async(dispatch_get_main_queue(), ^{
      if (callback) callback(userData, niminoString(body));
    });
    [body release];
  }
}

- (void)webView:(WKWebView *)webView
 decidePolicyForNavigationAction:(WKNavigationAction *)action
 decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
  (void)webView;
  NSString *url = action.request.URL.absoluteString;
  BOOL allowed = YES;
  if (self.context && self.context->navigationStartingCallback)
    allowed = self.context->navigationStartingCallback(self.context->userData, niminoString(url)) != 0;
  decisionHandler(allowed ? WKNavigationActionPolicyAllow : WKNavigationActionPolicyCancel);
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
  (void)navigation;
  if (self.context && self.context->navigationCompletedCallback) {
    MacNavigationCallback callback = self.context->navigationCompletedCallback;
    void *userData = self.context->userData;
    NSString *url = [webView.URL.absoluteString copy];
    dispatch_async(dispatch_get_main_queue(), ^{
      if (callback) callback(userData, niminoString(url), 1);
    });
    [url release];
  }
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation
       withError:(NSError *)error {
  (void)navigation;
  if (self.context && self.context->errorCallback)
    self.context->errorCallback(self.context->userData, "webview.navigate",
                                niminoString(error.localizedDescription));
  if (self.context && self.context->navigationCompletedCallback)
    self.context->navigationCompletedCallback(self.context->userData,
      niminoString(webView.URL.absoluteString), 0);
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation
       withError:(NSError *)error {
  [self webView:webView didFailNavigation:navigation withError:error];
}

- (WKWebView *)webView:(WKWebView *)webView
 createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration
 forNavigationAction:(WKNavigationAction *)navigationAction
      windowFeatures:(WKWindowFeatures *)windowFeatures {
  (void)webView; (void)configuration;
  if (!self.context || !self.context->newWindowCallback) return nil;
  NSString *url = navigationAction.request.URL.absoluteString;
  BOOL positionKnown = windowFeatures && windowFeatures.x && windowFeatures.y;
  BOOL sizeKnown = windowFeatures && windowFeatures.width && windowFeatures.height;
  int x = positionKnown ? windowFeatures.x.intValue : 0;
  int y = positionKnown ? windowFeatures.y.intValue : 0;
  int width = sizeKnown ? windowFeatures.width.intValue : 0;
  int height = sizeKnown ? windowFeatures.height.intValue : 0;
  (void)self.context->newWindowCallback(self.context->userData, niminoString(url),
    positionKnown, x, y, sizeKnown, width, height, 1, 0);
  return nil;
}

- (void)webView:(WKWebView *)webView
 decidePolicyForNavigationResponse:(WKNavigationResponse *)response
 decisionHandler:(void (^)(WKNavigationResponsePolicy))decisionHandler {
  (void)webView;
  if (response.canShowMIMEType) {
    decisionHandler(WKNavigationResponsePolicyAllow);
    return;
  }
  NSString *url = response.response.URL.absoluteString ?: @"";
  BOOL accepted = self.context && self.context->downloadStartingCallback &&
    self.context->downloadStartingCallback(self.context->userData, niminoString(url)) != 0;
  decisionHandler(accepted ? WKNavigationResponsePolicyDownload : WKNavigationResponsePolicyCancel);
}

- (void)webView:(WKWebView *)webView
 didBecomeDownload:(WKDownload *)download {
  (void)webView;
  download.delegate = self;
  if (!self.observedDownloads)
    self.observedDownloads = [[[NSHashTable alloc] initWithOptions:NSHashTableStrongMemory
                                                            capacity:0] autorelease];
  if (![self.observedDownloads containsObject:download]) {
    [download.progress addObserver:self forKeyPath:@"fractionCompleted"
                            options:NSKeyValueObservingOptionNew context:download];
    [self.observedDownloads addObject:download];
  }
  if (self.context && self.context->downloadEventCallback)
    self.context->downloadEventCallback(self.context->userData,
      niminoString(download.originalRequest.URL.absoluteString), 0, 0.0);
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey, id> *)change
                       context:(void *)context {
  if ([keyPath isEqualToString:@"fractionCompleted"] &&
      [object isKindOfClass:[NSProgress class]] && context != NULL) {
    double progress = [change[NSKeyValueChangeNewKey] doubleValue];
    progress = MIN(1.0, MAX(0.0, progress));
    WKDownload *download = (__bridge WKDownload *)context;
    if (self.context && self.context->downloadEventCallback)
      self.context->downloadEventCallback(self.context->userData,
        niminoString(download.originalRequest.URL.absoluteString), 1, progress);
    return;
  }
  [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (void)removeProgressObserverFromDownload:(WKDownload *)download {
  if (!download || !self.observedDownloads ||
      ![self.observedDownloads containsObject:download]) return;
  @try {
    [download.progress removeObserver:self forKeyPath:@"fractionCompleted" context:download];
  } @catch (NSException *exception) {
    (void)exception;
  }
  [self.observedDownloads removeObject:download];
}

- (void)dealloc {
  for (WKDownload *download in [self.observedDownloads allObjects])
    [self removeProgressObserverFromDownload:download];
  [_observedDownloads release];
  [super dealloc];
}

- (void)download:(WKDownload *)download
 decideDestinationUsingResponse:(NSURLResponse *)response
 suggestedFilename:(NSString *)suggestedFilename
 completionHandler:(void (^)(NSURL *))completionHandler {
  (void)response;
  NSString *url = download.originalRequest.URL.absoluteString ?: @"";
  const char *custom = NULL;
  if (self.context && self.context->downloadPathCallback)
    custom = self.context->downloadPathCallback(self.context->userData, niminoString(url));
  NSString *path = custom && custom[0] ? [NSString stringWithUTF8String:custom] : nil;
  if (!path || path.length == 0) {
    NSArray *directories = NSSearchPathForDirectoriesInDomains(NSDownloadsDirectory, NSUserDomainMask, YES);
    NSString *directory = directories.count > 0 ? directories[0] : NSTemporaryDirectory();
    path = [directory stringByAppendingPathComponent:suggestedFilename.length > 0 ? suggestedFilename : @"download"];
  }
  completionHandler([NSURL fileURLWithPath:path]);
}

- (void)downloadDidFinish:(WKDownload *)download {
  [self removeProgressObserverFromDownload:download];
  if (self.context && self.context->downloadEventCallback)
    self.context->downloadEventCallback(self.context->userData,
      niminoString(download.originalRequest.URL.absoluteString), 2, 1.0);
}

- (void)download:(WKDownload *)download didFailWithError:(NSError *)error
      resumeData:(NSData *)resumeData {
  (void)resumeData;
  [self removeProgressObserverFromDownload:download];
  if (self.context && self.context->downloadEventCallback)
    self.context->downloadEventCallback(self.context->userData,
      niminoString(download.originalRequest.URL.absoluteString), 3, 0.0);
  if (self.context && self.context->errorCallback)
    self.context->errorCallback(self.context->userData, "webview.download",
      niminoString(error.localizedDescription));
}

- (void)webView:(WKWebView *)webView requestMediaCapturePermissionForOrigin:( WKSecurityOrigin *)origin
 initiatedByFrame:(WKFrameInfo *)frame type:(WKMediaCaptureType)type
 decisionHandler:(void (^)(WKPermissionDecision))decisionHandler API_AVAILABLE(macos(12.0)) {
  (void)webView; (void)frame;
  NSString *url = origin.protocol.length > 0 ? [NSString stringWithFormat:@"%@://%@", origin.protocol, origin.host] : @"";
  BOOL allowed = YES;
  if (type == WKMediaCaptureTypeMicrophone || type == WKMediaCaptureTypeCameraAndMicrophone)
    allowed = allowed && self.context && self.context->permissionCallback &&
      self.context->permissionCallback(self.context->userData, "microphone", niminoString(url)) != 0;
  if (type == WKMediaCaptureTypeCamera || type == WKMediaCaptureTypeCameraAndMicrophone)
    allowed = allowed && self.context && self.context->permissionCallback &&
      self.context->permissionCallback(self.context->userData, "camera", niminoString(url)) != 0;
  decisionHandler(allowed ? WKPermissionDecisionGrant : WKPermissionDecisionDeny);
}

- (void)webView:(WKWebView *)webView
 didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *))completionHandler {
  if (self.context && self.context->ignoreCertificateErrors &&
      [challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
    completionHandler(NSURLSessionAuthChallengeUseCredential,
                      [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust]);
  } else {
    (void)webView;
    completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
  }
}
@end

void *nimino_macos_app_create(void *userData) {
  MacAppContext *context = calloc(1, sizeof(MacAppContext));
  if (!context) return NULL;
  context->userData = userData;
  context->application = [NSApplication sharedApplication];
  [context->application setActivationPolicy:NSApplicationActivationPolicyRegular];
  context->pendingDeepLinks = [NSMutableArray new];
  context->stoppedSchemeTasks = [NSMutableSet new];
  context->applicationDelegate = [NiminoApplicationDelegate new];
  context->applicationDelegate.context = context;
  context->application.delegate = context->applicationDelegate;
  return context;
}

int nimino_macos_app_run(void *opaque, void *idle) {
  MacAppContext *context = (MacAppContext *)opaque;
  if (!context || !context->application) return -1;
  g_idleCallback = (MacIdleCallback)idle;
  context->timer = [NSTimer scheduledTimerWithTimeInterval:0.01
      repeats:YES block:^(NSTimer *timer) { (void)timer; if (g_idleCallback) g_idleCallback(context->userData); }];
  [context->application activateIgnoringOtherApps:YES];
  [context->application run];
  [context->timer invalidate];
  context->timer = nil;
  g_idleCallback = NULL;
  return 0;
}

void nimino_macos_app_stop(void *opaque) {
  MacAppContext *context = (MacAppContext *)opaque;
  if (!context || !context->application) return;
  dispatch_async(dispatch_get_main_queue(), ^{
    [context->application stop:nil];
    [context->application postEvent:[NSEvent otherEventWithType:NSEventTypeApplicationDefined
        location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil subtype:0 data1:0 data2:0]
        atStart:YES];
  });
}

void nimino_macos_app_dispose(void *opaque) {
  MacAppContext *context = (MacAppContext *)opaque;
  if (!context) return;
  if (context->timer) {
    [context->timer invalidate];
    context->timer = nil;
  }
  g_idleCallback = NULL;
  for (MacWindowContext *window = context->windows; window;) {
    MacWindowContext *next = window->next;
    nimino_macos_window_dispose(window);
    window = next;
  }
  context->windows = NULL;
  [context->application setMainMenu:nil];
  if (context->statusItem)
    [[NSStatusBar systemStatusBar] removeStatusItem:context->statusItem];
  [context->statusItem release]; context->statusItem = nil;
  [context->trayTarget release]; context->trayTarget = nil;
  [NSEvent removeMonitor:context->shortcutMonitor];
  [NSEvent removeMonitor:context->localShortcutMonitor];
  context->shortcutMonitor = nil;
  context->localShortcutMonitor = nil;
  [context->shortcutKey release]; context->shortcutKey = nil;
  [context->menu release]; context->menu = nil;
  [context->menuTarget release]; context->menuTarget = nil;
  if ([NSBundle mainBundle].bundleIdentifier.length > 0 &&
      [UNUserNotificationCenter currentNotificationCenter].delegate == context->notificationDelegate)
    [UNUserNotificationCenter currentNotificationCenter].delegate = nil;
  [context->notificationDelegate release]; context->notificationDelegate = nil;
  if (context->application.delegate == context->applicationDelegate)
    context->application.delegate = nil;
  [context->applicationDelegate release]; context->applicationDelegate = nil;
  [context->pendingDeepLinks release]; context->pendingDeepLinks = nil;
  [context->stoppedSchemeTasks release]; context->stoppedSchemeTasks = nil;
  [context->schemeHandler release]; context->schemeHandler = nil;
  [context->scheme release]; context->scheme = nil;
  context->menuCallback = NULL;
  context->trayCallback = NULL;
  context->shortcutCallback = NULL;
  context->notificationCallback = NULL;
  context->deepLinkCallback = NULL;
  context->reopenCallback = NULL;
  free(context);
}

void nimino_macos_app_post_to_ui(void *opaque, void *callback) {
  MacAppContext *context = (MacAppContext *)opaque;
  if (!context || !callback) return;
  MacIdleCallback task = (MacIdleCallback)callback;
  dispatch_async(dispatch_get_main_queue(), ^{ task(context->userData); });
}

void nimino_macos_app_install_menu(void *opaque, const char *title, uint32_t *ids,
                                   const char **titles, const char **groups,
                                   const char **keyEquivalents, const char **predefined,
                                   int *enabled, int count, void *callback) {
  MacAppContext *context = (MacAppContext *)opaque;
  if (!context) return;
  [context->menu release];
  [context->menuTarget release];
  context->menuTarget = [NiminoMenuTarget new];
  context->menuTarget.context = context;
  context->menuCallback = (MacMenuCallback)callback;
  NSMenu *main = [[NSMenu alloc] initWithTitle:@"Nimino"];
  main.autoenablesItems = NO;
  NSString *applicationTitle = title ? [NSString stringWithUTF8String:title] : @"Nimino";
  NSString *currentGroup = nil;
  NSMenu *submenu = nil;
  NSMenuItem *root = nil;
  for (int i = 0; i < count; i++) {
    NSString *itemTitle = titles[i] ? [NSString stringWithUTF8String:titles[i]] : @"";
    NSString *group = groups && groups[i] && groups[i][0]
      ? [NSString stringWithUTF8String:groups[i]] : applicationTitle;
    if (!currentGroup || ![currentGroup isEqualToString:group]) {
      [submenu release];
      [root release];
      [currentGroup release];
      currentGroup = [group copy];
      root = [[NSMenuItem alloc] initWithTitle:group action:nil keyEquivalent:@""];
      submenu = [[NSMenu alloc] initWithTitle:group];
      submenu.autoenablesItems = NO;
      [root setSubmenu:submenu];
      [main addItem:root];
    }
    NSString *predefinedName = predefined && predefined[i] ?
      [NSString stringWithUTF8String:predefined[i]] : @"";
    SEL predefinedAction = nil;
    if ([predefinedName isEqualToString:@"about"]) predefinedAction = @selector(orderFrontStandardAboutPanel:);
    else if ([predefinedName isEqualToString:@"hide"]) predefinedAction = @selector(hide:);
    else if ([predefinedName isEqualToString:@"hideOthers"]) predefinedAction = @selector(hideOtherApplications:);
    else if ([predefinedName isEqualToString:@"showAll"]) predefinedAction = @selector(unhideAllApplications:);
    else if ([predefinedName isEqualToString:@"quit"]) predefinedAction = @selector(terminate:);
    else if ([predefinedName isEqualToString:@"undo"]) predefinedAction = @selector(undo:);
    else if ([predefinedName isEqualToString:@"redo"]) predefinedAction = @selector(redo:);
    else if ([predefinedName isEqualToString:@"cut"]) predefinedAction = @selector(cut:);
    else if ([predefinedName isEqualToString:@"copy"]) predefinedAction = @selector(copy:);
    else if ([predefinedName isEqualToString:@"paste"]) predefinedAction = @selector(paste:);
    else if ([predefinedName isEqualToString:@"pasteAndMatchStyle"]) predefinedAction = @selector(pasteAsPlainText:);
    else if ([predefinedName isEqualToString:@"selectAll"]) predefinedAction = @selector(selectAll:);
    else if ([predefinedName isEqualToString:@"closeWindow"]) predefinedAction = @selector(performClose:);
    else if ([predefinedName isEqualToString:@"minimize"]) predefinedAction = @selector(performMiniaturize:);
    else if ([predefinedName isEqualToString:@"maximize"]) predefinedAction = @selector(performZoom:);
    else if ([predefinedName isEqualToString:@"fullscreen"]) predefinedAction = @selector(toggleFullScreen:);
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:itemTitle
      action:predefinedAction ? predefinedAction : @selector(activate:)
      keyEquivalent:@""];
    if ([predefinedName isEqualToString:@"services"]) {
      item.submenu = context->application.servicesMenu;
      item.action = nil;
      item.target = nil;
    } else if (!predefinedAction) {
      item.target = context->menuTarget;
    }
    item.tag = (NSInteger)ids[i];
    item.enabled = enabled[i] != 0;
    if (keyEquivalents && keyEquivalents[i] && keyEquivalents[i][0]) {
      NSString *equivalent = [NSString stringWithUTF8String:keyEquivalents[i]];
      NSArray *tokens = [equivalent componentsSeparatedByString:@"+"];
      NSString *key = [(NSString *)tokens.lastObject lowercaseString];
      NSEventModifierFlags modifiers = 0;
      for (NSUInteger tokenIndex = 0; tokenIndex + 1 < tokens.count; tokenIndex++) {
        NSString *token = [tokens[tokenIndex] lowercaseString];
        if ([token isEqualToString:@"cmd"] || [token isEqualToString:@"command"])
          modifiers |= NSEventModifierFlagCommand;
        else if ([token isEqualToString:@"ctrl"] || [token isEqualToString:@"control"])
          modifiers |= NSEventModifierFlagControl;
        else if ([token isEqualToString:@"alt"] || [token isEqualToString:@"option"])
          modifiers |= NSEventModifierFlagOption;
        else if ([token isEqualToString:@"shift"])
          modifiers |= NSEventModifierFlagShift;
      }
      item.keyEquivalent = key;
      item.keyEquivalentModifierMask = modifiers;
    }
    [submenu addItem:item];
    [item release];
  }
  [currentGroup release];
  [submenu release];
  [root release];
  [context->application setMainMenu:main];
  context->menu = main;
}

void nimino_macos_app_remove_menu(void *opaque) {
  MacAppContext *context = (MacAppContext *)opaque;
  if (!context) return;
  [context->application setMainMenu:nil];
  [context->menu release]; context->menu = nil;
  [context->menuTarget release]; context->menuTarget = nil;
  context->menuCallback = NULL;
}

int nimino_macos_app_install_tray(void *opaque, uint32_t *ids, const char **titles,
                                  int *enabled, int count, void *callback) {
  MacAppContext *context = (MacAppContext *)opaque;
  if (!context || count <= 0 || !callback) return 0;
  [context->statusItem release];
  [context->trayTarget release];
  context->trayTarget = [NiminoMenuTarget new];
  context->trayTarget.context = context;
  context->trayTarget.tray = YES;
  context->trayCallback = (MacMenuCallback)callback;
  context->statusItem = [[[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength] retain];
  context->statusItem.button.title = @"Nimino";
  context->statusItem.button.target = context->trayTarget;
  context->statusItem.button.action = @selector(activateButton:);
  NSMenu *menu = [[[NSMenu alloc] initWithTitle:@"Nimino"] autorelease];
  for (int i = 0; i < count; ++i) {
    NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle:titles[i] ? [NSString stringWithUTF8String:titles[i]] : @""
      action:@selector(activate:) keyEquivalent:@""] autorelease];
    item.target = context->trayTarget;
    item.tag = (NSInteger)ids[i];
    item.enabled = enabled[i] != 0;
    [menu addItem:item];
  }
  context->statusItem.menu = menu;
  return context->statusItem != nil ? 1 : 0;
}

void nimino_macos_app_remove_tray(void *opaque) {
  MacAppContext *context = (MacAppContext *)opaque;
  if (!context) return;
  if (context->statusItem)
    [[NSStatusBar systemStatusBar] removeStatusItem:context->statusItem];
  [context->statusItem release]; context->statusItem = nil;
  [context->trayTarget release]; context->trayTarget = nil;
  context->trayCallback = NULL;
}

int nimino_macos_app_set_tray_icon(void *opaque, const char *path) {
  MacAppContext *context = (MacAppContext *)opaque;
  if (!context || !context->statusItem || !path || path[0] == '\0') return 0;
  NSString *value = [NSString stringWithUTF8String:path];
  NSImage *image = [[[NSImage alloc] initWithContentsOfFile:value] autorelease];
  if (!image) return 0;
  image.template = NO;
  context->statusItem.button.image = image;
  context->statusItem.button.title = @"";
  return 1;
}

static BOOL nimino_macos_shortcut_matches(MacAppContext *context, NSEvent *event) {
  if (!context || !event || !context->shortcutKey) return NO;
  NSEventModifierFlags flags = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
  if (flags != context->shortcutModifiers) return NO;
  NSString *characters = event.charactersIgnoringModifiers.lowercaseString;
  return [characters isEqualToString:context->shortcutKey];
}

int nimino_macos_app_set_activation_shortcut(void *opaque, const char *shortcut, void *callback) {
  MacAppContext *context = (MacAppContext *)opaque;
  if (!context || !shortcut || !callback || shortcut[0] == '\0') return 0;
  NSString *value = [NSString stringWithUTF8String:shortcut];
  NSArray *parts = [value componentsSeparatedByString:@"+"];
  if (parts.count < 2) return 0;
  NSUInteger modifiers = 0;
  NSString *key = nil;
  for (NSString *part in parts) {
    NSString *token = part.lowercaseString;
    if ([token isEqualToString:@"cmd"] || [token isEqualToString:@"command"] ||
        [token isEqualToString:@"cmdorctrl"])
      modifiers |= NSEventModifierFlagCommand;
    else if ([token isEqualToString:@"ctrl"] || [token isEqualToString:@"control"])
      modifiers |= NSEventModifierFlagControl;
    else if ([token isEqualToString:@"shift"])
      modifiers |= NSEventModifierFlagShift;
    else if ([token isEqualToString:@"alt"] || [token isEqualToString:@"option"])
      modifiers |= NSEventModifierFlagOption;
    else if ([token isEqualToString:@"space"])
      key = @" ";
    else if (token.length == 1)
      key = token;
    else
      return 0;
  }
  if (!key || modifiers == 0) return 0;
  [NSEvent removeMonitor:context->shortcutMonitor];
  [NSEvent removeMonitor:context->localShortcutMonitor];
  context->shortcutMonitor = nil;
  context->localShortcutMonitor = nil;
  [context->shortcutKey release];
  context->shortcutKey = [key copy];
  context->shortcutModifiers = modifiers;
  context->shortcutCallback = (MacIdleCallback)callback;
  context->shortcutMonitor = [NSEvent addGlobalMonitorForEventsMatchingMask:NSEventMaskKeyDown
    handler:^(NSEvent *event) {
      if (nimino_macos_shortcut_matches(context, event) && context->shortcutCallback)
        context->shortcutCallback(context->userData);
    }];
  context->localShortcutMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown
    handler:^NSEvent *(NSEvent *event) {
      if (nimino_macos_shortcut_matches(context, event) && context->shortcutCallback)
        context->shortcutCallback(context->userData);
      return event;
    }];
  return context->shortcutMonitor || context->localShortcutMonitor ? 1 : 0;
}

void nimino_macos_app_remove_activation_shortcut(void *opaque) {
  MacAppContext *context = (MacAppContext *)opaque;
  if (!context) return;
  [NSEvent removeMonitor:context->shortcutMonitor];
  [NSEvent removeMonitor:context->localShortcutMonitor];
  context->shortcutMonitor = nil;
  context->localShortcutMonitor = nil;
  [context->shortcutKey release]; context->shortcutKey = nil;
  context->shortcutCallback = NULL;
}

int nimino_macos_app_set_notification_callback(void *opaque, void *callback) {
  MacAppContext *context = (MacAppContext *)opaque;
  if (!context || !callback) return 0;
  context->notificationCallback = (MacNotificationCallback)callback;
  [context->notificationDelegate release];
  context->notificationDelegate = [NiminoNotificationDelegate new];
  context->notificationDelegate.context = context;
  /* UserNotifications raises an exception for command-line binaries that do
   * not have an application bundle. Keep registration idempotent for native
   * unit/smoke tests; packaged .app processes take the full path below. */
  if ([NSBundle mainBundle].bundleIdentifier.length == 0)
    return 1;
  UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
  center.delegate = context->notificationDelegate;
  [center requestAuthorizationWithOptions:(UNAuthorizationOptionAlert |
                                            UNAuthorizationOptionSound |
                                            UNAuthorizationOptionBadge)
                         completionHandler:^(BOOL granted, NSError *error) {
    if (!granted || error)
      niminoLogNotificationFailure("requestAuthorization", error);
  }];
  return 1;
}

int nimino_macos_app_set_deep_link_callback(void *opaque, void *callback) {
  MacAppContext *context = (MacAppContext *)opaque;
  if (!context || !callback || !context->applicationDelegate) return 0;
  context->deepLinkCallback = (MacDeepLinkCallback)callback;
  NSArray *pending = [context->pendingDeepLinks copy];
  for (NSString *url in pending)
    context->deepLinkCallback(context->userData, niminoString(url));
  [pending release];
  [context->pendingDeepLinks removeAllObjects];
  return 1;
}

int nimino_macos_app_set_reopen_callback(void *opaque, void *callback) {
  MacAppContext *context = (MacAppContext *)opaque;
  if (!context || !callback || !context->applicationDelegate) return 0;
  context->reopenCallback = (MacReopenCallback)callback;
  return 1;
}

int nimino_macos_app_send_notification(void *opaque, const char *identifier,
                                       const char *title, const char *body) {
  MacAppContext *context = (MacAppContext *)opaque;
  if (!context || !title) return 0;
  if ([NSBundle mainBundle].bundleIdentifier.length == 0) return 0;
  if (!niminoHasAppleIssuedSigning()) {
    niminoLogNotificationFailure("Apple-issued signing check", nil);
    return 0;
  }
  UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
  content.title = [NSString stringWithUTF8String:title];
  content.body = body ? [NSString stringWithUTF8String:body] : @"";
  NSString *requestId = identifier ? [NSString stringWithUTF8String:identifier] : @"nimino";
  UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:requestId
      content:content trigger:nil];
  [[UNUserNotificationCenter currentNotificationCenter]
      addNotificationRequest:request withCompletionHandler:^(NSError *error) {
    if (error)
      niminoLogNotificationFailure("addNotificationRequest", error);
  }];
  [content release];
  return 1;
}

int nimino_macos_app_set_dock_badge(void *opaque, const char *label) {
  MacAppContext *context = (MacAppContext *)opaque;
  if (!context || !context->application) return 0;
  NSString *value = label && label[0] ? [NSString stringWithUTF8String:label] : nil;
  context->application.dockTile.badgeLabel = value;
  return 1;
}

int nimino_macos_app_register_scheme(void *opaque, const char *scheme, void *callback) {
  MacAppContext *context = (MacAppContext *)opaque;
  if (!context || !scheme || !scheme[0] || !callback) return 0;
  [context->scheme release];
  context->scheme = [[NSString alloc] initWithUTF8String:scheme];
  context->schemeCallback = (MacSchemeCallback)callback;
  [context->schemeHandler release];
  context->schemeHandler = [NiminoSchemeHandler new];
  context->schemeHandler.context = context;
  return context->scheme && context->schemeHandler ? 1 : 0;
}

void nimino_macos_scheme_respond(void *appOpaque, void *taskOpaque, int status, const char *mimeType,
                                 const char *body) {
  MacAppContext *context = (MacAppContext *)appOpaque;
  id<WKURLSchemeTask> task = (id<WKURLSchemeTask>)taskOpaque;
  if (!task) return;
  if (context && [context->stoppedSchemeTasks containsObject:task]) {
    [context->stoppedSchemeTasks removeObject:task];
    return;
  }
  NSString *mime = mimeType && mimeType[0] ? [NSString stringWithUTF8String:mimeType] : @"application/octet-stream";
  NSData *data = body ? [NSData dataWithBytes:body length:strlen(body)] : [NSData data];
  NSURLResponse *response = [[NSURLResponse alloc] initWithURL:task.request.URL
      MIMEType:mime expectedContentLength:(NSInteger)data.length textEncodingName:@"utf-8"];
  if (status < 100 || status > 599) status = 500;
  NSHTTPURLResponse *httpResponse = [[NSHTTPURLResponse alloc] initWithURL:task.request.URL
      statusCode:status HTTPVersion:@"HTTP/1.1" headerFields:@{ @"Content-Type": mime }];
  [response release];
  [task didReceiveResponse:httpResponse];
  [httpResponse release];
  [task didReceiveData:data];
  [task didFinish];
}

void *nimino_macos_window_create(void *appOpaque, void *userData, const char *title,
                                 int width, int height, void *closeCallback,
                                 void *closedCallback, void *resizeCallback,
                                 void *moveCallback, void *fileDropCallback) {
  MacAppContext *app = (MacAppContext *)appOpaque;
  if (!app) return NULL;
  MacWindowContext *context = calloc(1, sizeof(MacWindowContext));
  if (!context) return NULL;
  context->userData = userData; context->app = app;
  context->closeCallback = (MacCloseCallback)closeCallback;
  context->closedCallback = (MacClosedCallback)closedCallback;
  context->resizeCallback = (MacResizeCallback)resizeCallback;
  context->moveCallback = (MacMoveCallback)moveCallback;
  context->fileDropCallback = (MacFileDropCallback)fileDropCallback;
  NSRect rect = NSMakeRect(0, 0, width, height);
  NSUInteger style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                      NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;
  context->window = [[NSWindow alloc] initWithContentRect:rect styleMask:style
                           backing:NSBackingStoreBuffered defer:NO];
  context->delegate = [NiminoWindowDelegate new];
  context->delegate.context = context;
  context->window.delegate = context->delegate;
  context->window.title = title ? [NSString stringWithUTF8String:title] : @"Nimino";
  context->dropView = [[NiminoDropView alloc] initWithFrame:rect];
  context->dropView.context = context;
  [context->dropView registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
  context->window.contentView = context->dropView;
  context->next = app->windows; app->windows = context;
  return context;
}

void nimino_macos_window_show(void *opaque) { MacWindowContext *c = opaque; if (c) { [c->window makeKeyAndOrderFront:nil]; [c->app->application activateIgnoringOtherApps:YES]; } }
void nimino_macos_window_hide(void *opaque) { MacWindowContext *c = opaque; if (c) [c->window orderOut:nil]; }
void nimino_macos_window_minimize(void *opaque) { MacWindowContext *c = opaque; if (c) [c->window miniaturize:nil]; }
void nimino_macos_window_maximize(void *opaque) { MacWindowContext *c = opaque; if (c) [c->window zoom:nil]; }
void nimino_macos_window_restore(void *opaque) { MacWindowContext *c = opaque; if (c) { if (c->window.isMiniaturized) [c->window deminiaturize:nil]; } }
void nimino_macos_window_focus(void *opaque) { nimino_macos_window_show(opaque); }
int nimino_macos_window_set_title(void *opaque, const char *title) { MacWindowContext *c=opaque; if (!c) return 0; c->window.title=title?[NSString stringWithUTF8String:title]:@""; return 1; }
int nimino_macos_window_set_size(void *opaque, int width, int height) { MacWindowContext *c=opaque; if (!c) return 0; [c->window setContentSize:NSMakeSize(width,height)]; return 1; }
int nimino_macos_window_set_position(void *opaque, int x, int y) { MacWindowContext *c=opaque; if (!c) return 0; [c->window setFrameOrigin:NSMakePoint(x,y)]; return 1; }
int nimino_macos_window_set_minimum_size(void *opaque, int width, int height) { MacWindowContext *c=opaque; if (!c || width <= 0 || height <= 0) return 0; [c->window setContentMinSize:NSMakeSize(width,height)]; return 1; }
int nimino_macos_window_set_resizable(void *opaque, int enabled) { MacWindowContext *c=opaque; if (!c) return 0; NSUInteger s=c->window.styleMask; if (enabled) s|=NSWindowStyleMaskResizable; else s&=~NSWindowStyleMaskResizable; c->window.styleMask=s; return 1; }
int nimino_macos_window_set_decorated(void *opaque, int enabled) { MacWindowContext *c=opaque; if (!c) return 0; NSUInteger s=c->window.styleMask; if (enabled) s|=NSWindowStyleMaskTitled; else s&=~NSWindowStyleMaskTitled; c->window.styleMask=s; return 1; }
int nimino_macos_window_set_title_bar_overlay(void *opaque, int enabled) {
  MacWindowContext *c = opaque;
  if (!c) return 0;
  if (enabled) {
    c->window.titleVisibility = NSWindowTitleHidden;
    c->window.titlebarAppearsTransparent = YES;
    c->window.styleMask |= NSWindowStyleMaskFullSizeContentView;
  } else {
    c->window.titleVisibility = NSWindowTitleVisible;
    c->window.titlebarAppearsTransparent = NO;
    c->window.styleMask &= ~NSWindowStyleMaskFullSizeContentView;
  }
  return 1;
}
int nimino_macos_window_set_fullscreen(void *opaque, int enabled) { MacWindowContext *c=opaque; if (!c) return 0; BOOL current=(c->window.styleMask & NSWindowStyleMaskFullScreen)!=0; if ((enabled!=0) != current) [c->window toggleFullScreen:nil]; return 1; }
int nimino_macos_window_set_always_on_top(void *opaque, int enabled) { MacWindowContext *c=opaque; if (!c) return 0; [c->window setLevel:enabled?NSFloatingWindowLevel:NSNormalWindowLevel]; return 1; }
int nimino_macos_window_set_dark_mode(void *opaque, int enabled) {
  MacWindowContext *c=opaque; if (!c) return 0;
  if (@available(macOS 10.14, *))
    c->window.appearance = enabled ? [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua] : nil;
  return 1;
}

void *nimino_macos_view_create(void *windowOpaque, void *userData, const char *userAgent,
                               const char *profilePath, const char *scheme,
                               const char *documentStartScript, const char *proxyUrl,
                               int incognito, int devTools,
                               int ignoreCertificateErrors, void *messageCallback,
                               void *errorCallback, void *newWindowCallback,
                               void *navigationStartingCallback, void *navigationCompletedCallback,
                               void *evalCallback, void *fileDropCallback,
                               void *permissionCallback, void *downloadStartingCallback,
                               void *downloadPathCallback, void *downloadEventCallback) {
  (void)scheme; (void)fileDropCallback;
  MacWindowContext *window = (MacWindowContext *)windowOpaque;
  if (!window) return NULL;
  MacViewContext *context = calloc(1, sizeof(MacViewContext));
  if (!context) return NULL;
  context->userData=userData; context->window=window;
  context->messageCallback=(MacMessageCallback)messageCallback;
  context->errorCallback=(MacErrorCallback)errorCallback;
  context->newWindowCallback=(MacNewWindowCallback)newWindowCallback;
  context->navigationStartingCallback=(MacBoolStringCallback)navigationStartingCallback;
  context->navigationCompletedCallback=(MacNavigationCallback)navigationCompletedCallback;
  context->evalCallback=(MacEvalCallback)evalCallback;
  context->permissionCallback=(MacPermissionCallback)permissionCallback;
  context->downloadStartingCallback=(MacDownloadStartingCallback)downloadStartingCallback;
  context->downloadPathCallback=(MacDownloadPathCallback)downloadPathCallback;
  context->downloadEventCallback=(MacDownloadEventCallback)downloadEventCallback;
  context->ignoreCertificateErrors=ignoreCertificateErrors != 0;
  WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
  if (incognito) {
    configuration.websiteDataStore = [WKWebsiteDataStore nonPersistentDataStore];
  } else if (profilePath && profilePath[0]) {
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(profilePath, (CC_LONG)strlen(profilePath), digest);
    NSUUID *identifier = [[NSUUID alloc] initWithUUIDBytes:digest];
    configuration.websiteDataStore = [WKWebsiteDataStore dataStoreForIdentifier:identifier];
    [identifier release];
  } else {
    configuration.websiteDataStore = [WKWebsiteDataStore defaultDataStore];
  }
  if (proxyUrl && proxyUrl[0]) {
    if (@available(macOS 14.0, *)) {
      NSString *proxy = [NSString stringWithUTF8String:proxyUrl];
      NSURL *proxyURL = [NSURL URLWithString:proxy];
      NSString *schemeName = proxyURL.scheme.lowercaseString;
      NSString *host = proxyURL.host;
      NSNumber *portNumber = proxyURL.port;
      NSInteger port = portNumber ? portNumber.integerValue :
        ([schemeName isEqualToString:@"socks5"] ? 1080 : 80);
      if (!proxyURL || !host || host.length == 0 ||
          (![schemeName isEqualToString:@"http"] && ![schemeName isEqualToString:@"socks5"]) ||
          port < 1 || port > 65535) {
        [configuration release];
        free(context);
        return NULL;
      }
      char portString[6];
      snprintf(portString, sizeof(portString), "%ld", (long)port);
      nw_endpoint_t endpoint = nw_endpoint_create_host(host.UTF8String, portString);
      nw_proxy_config_t proxyConfig = NULL;
      if (endpoint) {
        proxyConfig = [schemeName isEqualToString:@"socks5"]
          ? nw_proxy_config_create_socksv5(endpoint)
          : nw_proxy_config_create_http_connect(endpoint, NULL);
      }
      if (!proxyConfig) {
        if (endpoint) nw_release(endpoint);
        [configuration release];
        free(context);
        return NULL;
      }
      NSArray *proxies = [NSArray arrayWithObject:(id)proxyConfig];
      [configuration.websiteDataStore setValue:proxies forKey:@"proxyConfigurations"];
      nw_release(proxyConfig);
      nw_release(endpoint);
    } else {
      [configuration release];
      free(context);
      return NULL;
    }
  }
  context->delegate = [NiminoWebViewDelegate new]; context->delegate.context=context;
  [configuration.userContentController addScriptMessageHandler:context->delegate name:@"nimino"];
  if (documentStartScript && documentStartScript[0]) {
    NSString *source=[NSString stringWithUTF8String:documentStartScript];
    WKUserScript *script=[[WKUserScript alloc] initWithSource:source
      injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:NO];
    [configuration.userContentController addUserScript:script]; [script release];
  }
  if (window->app->scheme && window->app->schemeHandler)
    [configuration setURLSchemeHandler:window->app->schemeHandler forURLScheme:window->app->scheme];
  context->webView = [[WKWebView alloc] initWithFrame:window->dropView.bounds configuration:configuration];
  [configuration.preferences setValue:@(devTools != 0) forKey:@"developerExtrasEnabled"];
  [configuration release];
  context->webView.navigationDelegate=context->delegate; context->webView.UIDelegate=context->delegate;
  context->webView.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;
  if (userAgent && userAgent[0]) context->webView.customUserAgent=[NSString stringWithUTF8String:userAgent];
  [window->dropView addSubview:context->webView];
  context->next=window->views; window->views=context;
  return context;
}

void nimino_macos_view_dispose(void *opaque) {
  MacViewContext *c = opaque;
  if (!c || c->disposed) return;
  c->disposed = YES;
  macViewUnlink(c);
  if (c->webView) {
    [c->webView.configuration.userContentController removeScriptMessageHandlerForName:@"nimino"];
    c->webView.navigationDelegate = nil;
    c->webView.UIDelegate = nil;
    [c->webView removeFromSuperview];
    [c->webView release];
    c->webView = nil;
  }
  [c->delegate release];
  c->delegate = nil;
  if (c->pendingCallbacks == 0) free(c);
}
int nimino_macos_view_set_user_agent(void *opaque,const char *value){MacViewContext*c=opaque;if(!c||!c->webView)return 0;c->webView.customUserAgent=value?[NSString stringWithUTF8String:value]:nil;return 1;}
int nimino_macos_view_set_zoom(void *opaque,double factor){MacViewContext*c=opaque;if(!c||!c->webView)return 0;c->webView.pageZoom=factor;return 1;}
int nimino_macos_view_set_ignore_certificate_errors(void *opaque,int enabled){MacViewContext*c=opaque;if(!c)return 0;c->ignoreCertificateErrors=enabled!=0;return 1;}
int nimino_macos_view_set_devtools_enabled(void *opaque,int enabled){MacViewContext*c=opaque;if(!c||!c->webView)return 0;[c->webView.configuration.preferences setValue:@(enabled!=0) forKey:@"developerExtrasEnabled"];return 1;}
int nimino_macos_view_load_url(void *opaque,const char *url){MacViewContext*c=opaque;if(!c||!c->webView)return 0;NSURL*u=[NSURL URLWithString:[NSString stringWithUTF8String:url]];if(!u)return 0;[c->webView loadRequest:[NSURLRequest requestWithURL:u]];return 1;}
int nimino_macos_view_load_html(void *opaque,const char *html,const char *baseUrl){MacViewContext*c=opaque;if(!c||!c->webView)return 0;NSURL*u=baseUrl&&baseUrl[0]?[NSURL URLWithString:[NSString stringWithUTF8String:baseUrl]]:nil;[c->webView loadHTMLString:html?[NSString stringWithUTF8String:html]:@"" baseURL:u];return 1;}
int nimino_macos_view_set_document_start_script(void *opaque,const char *source){MacViewContext*c=opaque;if(!c||!c->webView)return 0;WKUserContentController*m=c->webView.configuration.userContentController;[m removeAllUserScripts];if(source&&source[0]){WKUserScript*s=[[WKUserScript alloc]initWithSource:[NSString stringWithUTF8String:source] injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:NO];[m addUserScript:s];[s release];}return 1;}
int nimino_macos_view_eval_javascript(void *opaque,const char *source,void *request){MacViewContext*c=opaque;if(!c||c->disposed||!c->webView||!c->evalCallback)return 0;MacEvalCallback callback=c->evalCallback;void*userData=c->userData;macViewRetainCallback(c);[c->webView evaluateJavaScript:[NSString stringWithUTF8String:source] completionHandler:^(id result,NSError*error){int succeeded=error?0:1;NSString*value=[niminoJSONDescription(result) copy];NSString*detail=[error.localizedDescription copy];dispatch_async(dispatch_get_main_queue(),^{if(callback)callback(userData,request,value?value.UTF8String:"",succeeded,detail?detail.UTF8String:"");[value release];[detail release];macViewReleaseCallback(c);});}];return 1;}
int nimino_macos_view_clear_browsing_data(void *opaque,uint32_t kinds,void *request,void *doneCallback){MacViewContext*c=opaque;if(!c||c->disposed||!c->webView)return 0;NSMutableSet*types=[NSMutableSet set];if(kinds&1)[types addObject:WKWebsiteDataTypeCookies];if(kinds&2)[types addObject:WKWebsiteDataTypeLocalStorage];if(kinds&4){[types addObject:WKWebsiteDataTypeMemoryCache];[types addObject:WKWebsiteDataTypeDiskCache];}MacClearCallback done=(MacClearCallback)doneCallback;void*userData=c->userData;macViewRetainCallback(c);[c->webView.configuration.websiteDataStore removeDataOfTypes:types modifiedSince:[NSDate dateWithTimeIntervalSince1970:0] completionHandler:^{if(done)done(userData,request,1);macViewReleaseCallback(c);}];return 1;}
int nimino_macos_view_get_cookies(void *opaque,const char *url,void *request,void *itemCallback,void *doneCallback){MacViewContext*c=opaque;if(!c||c->disposed||!c->webView)return 0;MacCookieCallback item=(MacCookieCallback)itemCallback;MacCookiesDoneCallback done=(MacCookiesDoneCallback)doneCallback;void*userData=c->userData;macViewRetainCallback(c);[c->webView.configuration.websiteDataStore.httpCookieStore getAllCookies:^(NSArray<NSHTTPCookie*>*cookies){NSURL*filter=url&&url[0]?[NSURL URLWithString:[NSString stringWithUTF8String:url]]:nil;for(NSHTTPCookie*cookie in cookies){if(filter&&!niminoCookieMatchesURL(cookie,filter))continue;if(item)item(userData,request,niminoString(cookie.name),niminoString(cookie.value),niminoString(cookie.domain),niminoString(cookie.path),cookie.isSecure,cookie.isHTTPOnly,(int64_t)cookie.expiresDate.timeIntervalSince1970);}if(done)done(userData,request,1);macViewReleaseCallback(c);}];return 1;}
static int nimino_cookie_operation(void*opaque,const char*n,const char*v,const char*d,const char*p,int secure,int httpOnly,int64_t expires,void*request,int remove,void*doneCallback){MacViewContext*c=opaque;if(!c||c->disposed||!c->webView)return 0;NSMutableDictionary*properties=[@{NSHTTPCookieName:[NSString stringWithUTF8String:n],NSHTTPCookieValue:[NSString stringWithUTF8String:v],NSHTTPCookieDomain:[NSString stringWithUTF8String:d],NSHTTPCookiePath:p&&p[0]?[NSString stringWithUTF8String:p]:@"/"} mutableCopy];if(expires>0)properties[NSHTTPCookieExpires]=[NSDate dateWithTimeIntervalSince1970:expires];NSHTTPCookie*cookie=[NSHTTPCookie cookieWithProperties:properties];[properties release];if(!cookie)return 0;WKHTTPCookieStore*s=c->webView.configuration.websiteDataStore.httpCookieStore;MacCookiesDoneCallback done=(MacCookiesDoneCallback)doneCallback;void*userData=c->userData;macViewRetainCallback(c);void(^completion)(void)=^{if(done)done(userData,request,1);macViewReleaseCallback(c);};if(remove)[s deleteCookie:cookie completionHandler:completion];else[s setCookie:cookie completionHandler:completion];return 1;}
int nimino_macos_view_set_cookie(void*o,const char*n,const char*v,const char*d,const char*p,int s,int h,int64_t e,void*r,void*done){return nimino_cookie_operation(o,n,v,d,p,s,h,e,r,0,done);}
int nimino_macos_view_delete_cookie(void*o,const char*n,const char*v,const char*d,const char*p,int s,int h,int64_t e,void*r,void*done){return nimino_cookie_operation(o,n,v,d,p,s,h,e,r,1,done);}

int nimino_macos_open_file_dialog(void *opaque,const char *title,const char *suggestedName,int save,int multiple,const char **paths,int capacity){MacWindowContext*c=opaque;if(!c)return -1;NSSavePanel*savePanel=nil;NSOpenPanel*openPanel=nil;if(save){savePanel=[NSSavePanel savePanel];savePanel.title=[NSString stringWithUTF8String:title];if(suggestedName&&suggestedName[0])savePanel.nameFieldStringValue=[NSString stringWithUTF8String:suggestedName];NSInteger result=[savePanel runModal];if(result!=NSModalResponseOK)return 0;NSURL*u=savePanel.URL;if(capacity>0)paths[0]=strdup(u.path.UTF8String);return 1;}openPanel=[NSOpenPanel openPanel];openPanel.title=[NSString stringWithUTF8String:title];openPanel.canChooseFiles=YES;openPanel.canChooseDirectories=NO;openPanel.allowsMultipleSelection=multiple!=0;NSInteger result=[openPanel runModal];if(result!=NSModalResponseOK)return 0;NSInteger count=MIN((NSInteger)capacity,(NSInteger)[openPanel.URLs count]);for(NSInteger i=0;i<count;i++)paths[i]=strdup([openPanel.URLs[i] path].UTF8String);return (int)count;}
void nimino_macos_free_string(const char *value){free((void*)value);}

void nimino_macos_window_dispose(void *opaque) {
  MacWindowContext *c = opaque;
  if (!c) return;
  for (MacViewContext *view = c->views; view;) {
    MacViewContext *next = view->next;
    nimino_macos_view_dispose(view);
    view = next;
  }
  c->views = NULL;
  if (c->app && c->app->windows == c)
    c->app->windows = c->next;
  else if (c->app) {
    for (MacWindowContext *cursor = c->app->windows; cursor; cursor = cursor->next) {
      if (cursor->next == c) {
        cursor->next = c->next;
        break;
      }
    }
  }
  [c->window setDelegate:nil];
  [c->window orderOut:nil];
  [c->window close];
  [c->dropView release];
  [c->delegate release];
  [c->window release];
  c->dropView = nil; c->delegate = nil; c->window = nil;
  free(c);
}
