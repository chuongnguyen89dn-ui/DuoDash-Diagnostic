#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>

static BOOL DDCarPlayWindow(UIWindow *w) {
    if (!w) return NO;
    UIScreen *s = w.screen;
    if (!s || s == UIScreen.mainScreen) return NO;
    CGSize z = s.bounds.size;
    return fabs(z.width-427.0)<3.0 && fabs(z.height-240.0)<3.0;
}

/*
 Evidence port from AiraW 1.7.1k:
 AiraW injects into com.apple.CarPlayApp, handles
 DBApplicationSceneViewController/CARApplicationSceneViewController and uses
 the private _setFullScreenEnabled: host path.  Do not copy AiraW code/binary;
 invoke only the host capability dynamically when that selector exists.
*/
static void DDEnableHostFullscreen(id obj) {
    if (!obj) return;
    SEL fs = NSSelectorFromString(@"_setFullScreenEnabled:");
    if ([obj respondsToSelector:fs])
        ((void(*)(id,SEL,BOOL))objc_msgSend)(obj,fs,YES);

    UIView *v = nil;
    if ([obj respondsToSelector:@selector(view)])
        v = ((id(*)(id,SEL))objc_msgSend)(obj,@selector(view));
    UIWindow *w = v.window;
    if (DDCarPlayWindow(w)) {
        CGRect b = w.screen.bounds;
        w.frame = b;
        v.frame = b;
        v.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    }
}

%group DDHost
%hook DBApplicationSceneViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    DDEnableHostFullscreen(self);
}
- (void)viewDidLayoutSubviews {
    %orig;
    DDEnableHostFullscreen(self);
}
%end

%hook CARApplicationSceneViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    DDEnableHostFullscreen(self);
}
- (void)viewDidLayoutSubviews {
    %orig;
    DDEnableHostFullscreen(self);
}
%end

%hook UIWindow
- (UIEdgeInsets)safeAreaInsets {
    UIEdgeInsets x=%orig;
    return DDCarPlayWindow(self)?UIEdgeInsetsZero:x;
}
%end

%hook UIView
- (UIEdgeInsets)safeAreaInsets {
    UIEdgeInsets x=%orig;
    return DDCarPlayWindow(self.window)?UIEdgeInsetsZero:x;
}
%end

%hook DBStatusBarWindow
- (void)setFrame:(CGRect)f {
    if (f.size.width>0) f.origin.x=-fabs(f.size.width);
    %orig(f);
}
%end
%end

%ctor {
    NSString *bid=NSBundle.mainBundle.bundleIdentifier ?: @"";
    NSString *proc=NSProcessInfo.processInfo.processName ?: @"";
    if ([bid isEqualToString:@"com.apple.CarPlayApp"] ||
        [bid isEqualToString:@"com.apple.CarPlay"] ||
        [proc containsString:@"CarPlay"]) {
        %init(DDHost);
    }
}
