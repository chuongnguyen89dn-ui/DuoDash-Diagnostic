#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

static BOOL DDIsCarPlayWindow(UIWindow *w) {
    if (!w) return NO;
    UIScreen *s = w.screen;
    if (!s || s == UIScreen.mainScreen) return NO;
    CGSize z = s.bounds.size;
    return (fabs(z.width - 427.0) < 2.0 && fabs(z.height - 240.0) < 2.0);
}

%group CarPlayFix

%hook UIWindow
- (UIEdgeInsets)safeAreaInsets {
    UIEdgeInsets insets = %orig;
    if (DDIsCarPlayWindow(self)) return UIEdgeInsetsZero;
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

// CarPlay navigation/status sidebar. The known full-screen geometry has this
// 45pt window at x=-45 instead of x=0. Preserve the window (do not hide it)
// but move it completely off-screen so DuoDash can use the full 427pt width.
%hook DBStatusBarWindow
- (void)setFrame:(CGRect)frame {
    if (frame.size.width > 0.0) frame.origin.x = -fabs(frame.size.width);
    %orig(frame);
}
- (void)layoutSubviews {
    %orig;
    UIWindow *w = (UIWindow *)self;
    CGRect f = w.frame;
    CGFloat targetX = -fabs(f.size.width);
    if (f.size.width > 0.0 && fabs(f.origin.x - targetX) > 0.1) {
        f.origin.x = targetX;
        w.frame = f;
    }
}
%end

%end

%ctor {
    NSString *p = NSProcessInfo.processInfo.processName;
    if ([p containsString:@"CarPlay"]) {
        %init(CarPlayFix);
    }
}
