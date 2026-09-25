#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

static BOOL DDIsCarPlayWindow(UIWindow *w) {
    if (!w) return NO;
    UIScreen *s = w.screen;
    if (!s || s == UIScreen.mainScreen) return NO;
    CGSize z = s.bounds.size;
    return (fabs(z.width - 427.0) < 2.0 && fabs(z.height - 240.0) < 2.0);
}

%hook UIWindow
- (UIEdgeInsets)safeAreaInsets {
    UIEdgeInsets insets = %orig;
    if (DDIsCarPlayWindow(self)) {
        // iPhone X reports 0/0/0/0 on this same 854x480 head unit.
        // iPhone 8 incorrectly reports a 20pt bottom inset, shrinking DuoDash.
        return UIEdgeInsetsZero;
    }
    return insets;
}
%end

%hook UIView
- (UIEdgeInsets)safeAreaInsets {
    UIEdgeInsets insets = %orig;
    UIWindow *w = self.window;
    if (DDIsCarPlayWindow(w)) return UIEdgeInsetsZero;
    return insets;
}
%end

%ctor {
    NSString *p = NSProcessInfo.processInfo.processName;
    if (![p containsString:@"CarPlay"]) return;
}
