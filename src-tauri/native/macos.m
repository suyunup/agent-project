#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <Carbon/Carbon.h>

// All functions and callbacks run on the main thread. No clipboard observer,
// keyboard logging, database, or network access is installed.
@interface ClipWeavePanel : NSPanel
@end
@implementation ClipWeavePanel
- (BOOL)canBecomeKeyWindow { return NO; }
- (BOOL)canBecomeMainWindow { return NO; }
@end
static ClipWeavePanel *overlayPanel;
static int navigationKey;
static BOOL handledKeyUps[128];
static CFMachPortRef tap;
static CFRunLoopSourceRef tapSource;
static BOOL enabled, busy, pending, invalidTarget, restoring, suppressV;
static NSString *captured;
static NSRunningApplication *targetApp;
static AXUIElementRef targetAX, targetWindow, targetElement;
static CFTypeRef targetRange;
static int captureAttempts;
static CFTimeInterval captureDeadline;
static NSPoint invocationPoint;
static uint64_t generation;
static int pasteOutcome;
static const char *lastError = "붙여넣기를 완료하지 못했습니다.";
const char *cw_error(void) { return lastError; }
static const int64_t ownEventTag = 0x434C495057454156;
static const NSUInteger maxBytes = 1024 * 1024;

static CFTypeRef attribute(AXUIElementRef object, CFStringRef name) {
    CFTypeRef value = NULL;
    if (object) AXUIElementCopyAttributeValue(object, name, &value);
    return value;
}
static BOOL sameAttribute(AXUIElementRef object, CFStringRef name, CFTypeRef expected) {
    CFTypeRef value = attribute(object, name);
    BOOL same = value && expected && CFEqual(value, expected);
    if (value) CFRelease(value);
    return same;
}
// Browser input elements can belong to a renderer PID. A focused element
// returned by the known application is authoritative even across processes.
static AXUIElementRef focusedElement(void) {
    AXUIElementRef element = (AXUIElementRef)attribute(targetAX, kAXFocusedUIElementAttribute);
    if (element) return element;
    AXUIElementRef system = AXUIElementCreateSystemWide();
    AXUIElementSetMessagingTimeout(system, 0.1);
    AXUIElementRef focusedApp = (AXUIElementRef)attribute(system, kAXFocusedApplicationAttribute);
    pid_t pid = 0;
    if (focusedApp && AXUIElementGetPid(focusedApp, &pid) == kAXErrorSuccess && pid == targetApp.processIdentifier) {
        element = (AXUIElementRef)attribute(system, kAXFocusedUIElementAttribute);
    }
    if (focusedApp) CFRelease(focusedApp);
    CFRelease(system);
    return element;
}
static void releaseTarget(void) {
    if (targetAX) CFRelease(targetAX);
    if (targetWindow) CFRelease(targetWindow);
    if (targetElement) CFRelease(targetElement);
    if (targetRange) CFRelease(targetRange);
    targetAX = targetWindow = targetElement = NULL;
    targetRange = NULL;
    targetApp = nil;
}
void cw_cancel(void) {
    generation++;
    busy = pending = restoring = NO;
    navigationKey = 0;
    captured = nil;
    pasteOutcome = 0;
    releaseTarget();
}
static BOOL fail(const char *message) { lastError = message; return NO; }
static BOOL validTarget(void) {
    if (invalidTarget) return fail("메뉴를 연 뒤 대상 앱이 변경되었습니다. 대상 입력창에서 다시 호출해 주세요.");
    if (!AXIsProcessTrusted()) return fail("접근성 권한이 해제되었습니다.");
    if (!targetApp || targetApp.terminated) return fail("원래 대상 앱이 종료되었습니다.");
    if (!targetWindow) return fail("호출 당시 대상 창 정보를 가져오지 못했습니다.");
    if (!targetElement) return fail("호출 당시 입력 요소 정보를 가져오지 못했습니다.");
    if (!sameAttribute(targetAX, kAXFocusedWindowAttribute, targetWindow))
        return fail("대상 앱의 창이 바뀌었거나 창 정보를 다시 읽지 못했습니다.");
    AXUIElementRef focused = focusedElement();
    BOOL sameFocus = focused && CFEqual(focused, targetElement);
    if (focused) CFRelease(focused);
    if (!sameFocus) return fail("대상 앱의 입력 요소가 바뀌었거나 포커스 정보를 다시 읽지 못했습니다.");
    if (targetRange && !sameAttribute(targetElement, kAXSelectedTextRangeAttribute, targetRange))
        return fail("원래 입력 위치의 커서 또는 선택 범위가 변경되었습니다.");
    return YES;
}
static CGEventRef callback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *context) {
    (void)proxy; (void)context;
    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        enabled = NO; invalidTarget = YES;
        return event; // Explicit re-enable required; never silently keep intercepting.
    }
    if (CGEventGetIntegerValueField(event, kCGEventSourceUserData) == ownEventTag) {
        if (!busy || !targetApp || invalidTarget ||
            NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier != targetApp.processIdentifier) {
            fail("키 전달 직전에 대상 앱이 변경되어 중단했습니다.");
            restoring = NO; pasteOutcome = -1; return NULL;
        }
        if (type == kCGEventKeyUp) { restoring = NO; pasteOutcome = 1; }
        return event;
    }
    int64_t key = CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
    if (type == kCGEventKeyUp && key >= 0 && key < 128 && handledKeyUps[key]) {
        handledKeyUps[key] = NO; return NULL;
    }
    if (busy && !invalidTarget && overlayPanel.visible && type == kCGEventKeyDown &&
        (key == 53 || key == 36 || key == 76 || key == 125 || key == 126)) {
        if (!CGEventGetIntegerValueField(event, kCGKeyboardEventAutorepeat)) {
            navigationKey = key == 53 ? 1 : (key == 125 ? 2 : (key == 126 ? 3 : 4));
        }
        handledKeyUps[key] = YES;
        return NULL;
    }
    if (key != 9) return event;
    if (type == kCGEventKeyUp) {
        if (suppressV) { suppressV = NO; return NULL; }
        return event;
    }
    if (type != kCGEventKeyDown) return event;
    if (suppressV) return NULL; // Consume repeats until matching key-up.
    CGEventFlags flags = CGEventGetFlags(event);
    if (!(flags & kCGEventFlagMaskCommand) || (flags & (kCGEventFlagMaskShift | kCGEventFlagMaskAlternate | kCGEventFlagMaskControl))) return event;
    if (!AXIsProcessTrusted() || IsSecureEventInputEnabled()) return event;
    if (busy) {
        if (invalidTarget) return event;
        suppressV = YES; return NULL;
    }
    if (!enabled) return event;
    NSRunningApplication *front = NSWorkspace.sharedWorkspace.frontmostApplication;
    if (!front || front.processIdentifier == NSProcessInfo.processInfo.processIdentifier) return event;
    // This is a user-triggered read, never a background clipboard collection.
    // AX IPC and window operations are deferred to cw_poll on the next UI tick.
    NSPasteboard *board = NSPasteboard.generalPasteboard;
    NSString *text = [board stringForType:NSPasteboardTypeString];
    if (!text.length || [text lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > maxBytes) return event;
    unichar zero = 0;
    if ([text rangeOfString:[NSString stringWithCharacters:&zero length:1]].location != NSNotFound) return event;
    captured = [text copy];
    targetApp = front;
    invocationPoint = NSEvent.mouseLocation;
    invalidTarget = NO;
    captureAttempts = 0;
    captureDeadline = CFAbsoluteTimeGetCurrent() + 4.0;
    busy = pending = suppressV = YES;
    enabled = NO; // One shot: consuming this call immediately disarms ordinary paste interception.
    generation++;
    return NULL;
}
int cw_permission(void) { return AXIsProcessTrusted() ? 1 : 0; }
void cw_request_permission(void) {
    NSDictionary *options = @{(__bridge NSString *)kAXTrustedCheckOptionPrompt: @YES};
    AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
}
int cw_available(void) { return tap && CGEventTapIsEnabled(tap) && AXIsProcessTrusted(); }
int cw_enabled(void) { return enabled && cw_available(); }
int cw_enable(int value) {
    if (!value) {
        enabled = NO;
        if (tap) CGEventTapEnable(tap, false);
        cw_cancel();
        suppressV = NO;
        return 1;
    }
    if (!AXIsProcessTrusted()) return 0;
    cw_cancel();
    if (!tap) {
        tap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionDefault,
            CGEventMaskBit(kCGEventKeyDown) | CGEventMaskBit(kCGEventKeyUp), callback, NULL);
        if (!tap) return 0;
        tapSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0);
        CFRunLoopAddSource(CFRunLoopGetMain(), tapSource, kCFRunLoopCommonModes);
        [NSWorkspace.sharedWorkspace.notificationCenter addObserverForName:NSWorkspaceDidActivateApplicationNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            NSRunningApplication *app = note.userInfo[NSWorkspaceApplicationKey];
            if (busy && app.processIdentifier != NSProcessInfo.processInfo.processIdentifier &&
                (!restoring || app.processIdentifier != targetApp.processIdentifier)) invalidTarget = YES;
        }];
    }
    CGEventTapEnable(tap, true);
    enabled = CGEventTapIsEnabled(tap);
    return enabled;
}
// Returned allocation is freed by cw_free after Rust copies it.
char *cw_poll(void) {
    if (!pending) return NULL;
    if (!cw_available()) { cw_cancel(); return NULL; }
    if (!targetApp || targetApp.terminated || NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier != targetApp.processIdentifier) invalidTarget = YES;
    if (!targetAX) {
        targetAX = AXUIElementCreateApplication(targetApp.processIdentifier);
        AXUIElementSetMessagingTimeout(targetAX, 0.1);
        targetWindow = (AXUIElementRef)attribute(targetAX, kAXFocusedWindowAttribute);
    }
    targetElement = focusedElement();
    if (!targetElement && !invalidTarget && CFAbsoluteTimeGetCurrent() < captureDeadline) {
        if (captureAttempts == 0) {
            // Electron documents this opt-in for assistive applications.
            // Unsupported apps simply return an AX error. Never change text.
            AXUIElementSetAttributeValue(targetAX, CFSTR("AXManualAccessibility"), kCFBooleanTrue);
            // Chromium requests enhanced accessibility and may enable it after
            // a two-second delay. Query again on subsequent ticks.
            AXUIElementSetAttributeValue(targetAX, CFSTR("AXEnhancedUserInterface"), kCFBooleanTrue);
        }
        captureAttempts++;
        return NULL; // Let the app build its AX tree without blocking our run loop.
    }
    pending = NO;
    if (!targetWindow) targetWindow = (AXUIElementRef)attribute(targetAX, kAXFocusedWindowAttribute);
    if (targetElement) AXUIElementSetMessagingTimeout(targetElement, 0.1);
    targetRange = attribute(targetElement, kAXSelectedTextRangeAttribute);
    char *result = strdup(captured.UTF8String);
    captured = nil;
    return result;
}
void cw_free(char *value) { free(value); }
void cw_show(void *pointer) {
    NSWindow *original = (__bridge NSWindow *)pointer;
    if (!overlayPanel) {
        overlayPanel = [[ClipWeavePanel alloc] initWithContentRect:original.contentView.bounds
            styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
            backing:NSBackingStoreBuffered defer:NO];
        overlayPanel.releasedWhenClosed = NO;
        overlayPanel.hidesOnDeactivate = NO;
        overlayPanel.level = NSFloatingWindowLevel;
        overlayPanel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary;
        // Tao continues to access its original contentView for window events.
        // Keep that view installed and only reparent its WebView children.
        for (NSView *child in [original.contentView.subviews copy]) {
            [child removeFromSuperview];
            child.frame = overlayPanel.contentView.bounds;
            child.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
            [overlayPanel.contentView addSubview:child];
        }
    }
    NSScreen *screen = NSScreen.mainScreen;
    for (NSScreen *candidate in NSScreen.screens) {
        if (NSPointInRect(invocationPoint, candidate.frame)) { screen = candidate; break; }
    }
    NSRect visible = screen.visibleFrame;
    NSRect frame = overlayPanel.frame;
    frame.origin.x = MAX(NSMinX(visible), MIN(invocationPoint.x + 12, NSMaxX(visible) - frame.size.width));
    frame.origin.y = MAX(NSMinY(visible), MIN(invocationPoint.y - frame.size.height - 12, NSMaxY(visible) - frame.size.height));
    [overlayPanel setFrame:frame display:YES];
    [overlayPanel orderFrontRegardless];
    // Do not activate ClipWeave or make the panel key: the target retains its caret.
}
void cw_hide(void) { [overlayPanel orderOut:nil]; }
int cw_key(void) { int key = navigationKey; navigationKey = 0; return key; }
int cw_copy(const char *text) {
    NSString *value = [NSString stringWithUTF8String:text];
    if (!value) return 0;
    [NSPasteboard.generalPasteboard clearContents];
    return [NSPasteboard.generalPasteboard setString:value forType:NSPasteboardTypeString] ? 1 : 0;
}
static void finishPaste(NSString *text, uint64_t token, int attempt) {
    if (!busy || token != generation) return;
    if (!validTarget()) { restoring = NO; pasteOutcome = -1; return; }
    pid_t front = NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier;
    if (front != targetApp.processIdentifier || (CGEventSourceFlagsState(kCGEventSourceStateCombinedSessionState) &
        (kCGEventFlagMaskCommand | kCGEventFlagMaskShift | kCGEventFlagMaskAlternate | kCGEventFlagMaskControl))) {
        if (attempt >= 25) { fail("대상 앱이 활성 상태가 아니거나 수정키가 계속 눌려 있어 중단했습니다."); restoring = NO; pasteOutcome = -1; return; }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ finishPaste(text, token, attempt + 1); });
        return;
    }
    if (!cw_copy(text.UTF8String)) { fail("클립보드 쓰기에 실패했습니다."); restoring = NO; pasteOutcome = -2; return; }
    CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStatePrivate);
    if (!source) { fail("붙여넣기 키 입력 소스를 생성하지 못했습니다."); restoring = NO; pasteOutcome = -3; return; }
    CGEventRef down = CGEventCreateKeyboardEvent(source, 9, true);
    CGEventRef up = CGEventCreateKeyboardEvent(source, 9, false);
    CFRelease(source);
    if (!down || !up) {
        if (down) CFRelease(down); if (up) CFRelease(up);
        fail("붙여넣기 키 이벤트를 생성하지 못했습니다."); restoring = NO; pasteOutcome = -3; return;
    }
    CGEventSetFlags(down, kCGEventFlagMaskCommand);
    CGEventSetFlags(up, kCGEventFlagMaskCommand);
    CGEventSetIntegerValueField(down, kCGEventSourceUserData, ownEventTag);
    CGEventSetIntegerValueField(up, kCGEventSourceUserData, ownEventTag);
    // Use the normal HID route so macOS performs normal shortcut dispatch.
    // Our session tap recognizes the marker and checks the foreground PID again.
    CGEventPost(kCGHIDEventTap, down);
    CGEventPost(kCGHIDEventTap, up);
    CFRelease(down); CFRelease(up);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 500 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        if (busy && restoring && token == generation) {
            fail("시스템에서 붙여넣기 키 전달을 확인하지 못했습니다.");
            restoring = NO; pasteOutcome = -3;
        }
    });
}
int cw_paste(const char *text) {
    if (!validTarget()) return 0;
    NSString *value = [NSString stringWithUTF8String:text];
    if (!value) return 0;
    restoring = YES;
    if (NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier != targetApp.processIdentifier) {
        fail("현재 활성 앱이 원래 대상 앱과 다릅니다."); restoring = NO; return 0;
    }
    uint64_t token = generation;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ finishPaste(value, token, 0); });
    return 1;
}
int cw_outcome(void) { int result = pasteOutcome; pasteOutcome = 0; return result; }
