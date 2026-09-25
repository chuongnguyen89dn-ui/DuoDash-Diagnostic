#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>

static BOOL DDIsCarPlayWindow(UIWindow *w) {
    if (!w) return NO;
    UIScreen *s = w.screen;
    if (!s || s == UIScreen.mainScreen) return NO;
    CGSize z = s.bounds.size;
    return (fabs(z.width - 427.0) < 2.0 && fabs(z.height - 240.0) < 2.0);
}

static void DDForceDuoDashFullscreenPreference(void) {
    // DuoDash 1.1.3 itself contains the supported layout values:
    // headunit_layout_area = carplay-fullscreen ("full").
    CFStringRef appID = CFSTR("com.sensetechlab.duodash.settings");
    CFPreferencesSetAppValue(CFSTR("headunit_layout_area"), CFSTR("carplay-fullscreen"), appID);
    CFPreferencesSetAppValue(CFSTR("carplay_content_insets"), CFSTR("0,0,0,0"), appID);
    CFPreferencesSetAppValue(CFSTR("carplay_content_inset"), CFSTR("0"), appID);
    CFPreferencesAppSynchronize(appID);

    // Also publish the same values in DuoDash's runtime bridge plist.
    NSString *path = @"/var/tmp/com.sensetechlab.appbridge.plist";
    NSMutableDictionary *d = [NSMutableDictionary dictionaryWithContentsOfFile:path];
    if (!d) d = [NSMutableDictionary dictionary];
    d[@"headunit_layout_area"] = @"carplay-fullscreen";
    d[@"carplay_content_insets"] = @"0,0,0,0";
    d[@"carplay_content_inset"] = @0;
    [d writeToFile:path atomically:YES];

    [[NSNotificationCenter defaultCenter] postNotificationName:@"com.sensetechlab.settings.changed" object:nil];
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
        DDForceDuoDashFullscreenPreference();
        %init(CarPlayFix);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            DDForceDuoDashFullscreenPreference();
        });
    }
}
