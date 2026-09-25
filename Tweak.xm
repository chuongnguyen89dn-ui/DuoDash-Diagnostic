#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <unistd.h>

static NSString *DDPath(void) { return @"/var/mobile/Documents/DuoDash-geometry-live.txt"; }
static NSString *DDRect(CGRect r) { return [NSString stringWithFormat:@"{{%.2f,%.2f},{%.2f,%.2f}}",r.origin.x,r.origin.y,r.size.width,r.size.height]; }
static NSString *DDInsets(UIEdgeInsets i) { return [NSString stringWithFormat:@"{%.2f,%.2f,%.2f,%.2f}",i.top,i.left,i.bottom,i.right]; }
static void DDWrite(NSString *s) {
    NSFileManager *fm=[NSFileManager defaultManager];
    if(![fm fileExistsAtPath:DDPath()]) [fm createFileAtPath:DDPath() contents:nil attributes:nil];
    NSFileHandle *h=[NSFileHandle fileHandleForWritingAtPath:DDPath()];
    if(!h) return;
    [h seekToEndOfFile];
    [h writeData:[[s stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding]];
    [h closeFile];
}
static void DDDump(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIApplication *app=[UIApplication sharedApplication];
        NSMutableString *o=[NSMutableString stringWithFormat:@"\n=== %@ process=%@ ===\n",[NSDate date],[[NSProcessInfo processInfo] processName]];
        NSArray *screens=[UIScreen screens];
        [o appendFormat:@"screens=%lu\n",(unsigned long)[screens count]];
        for(NSUInteger i=0;i<[screens count];i++){
            UIScreen *s=[screens objectAtIndex:i];
            [o appendFormat:@"SCREEN[%lu] bounds=%@ nativeBounds=%@ scale=%.3f nativeScale=%.3f\n",(unsigned long)i,DDRect([s bounds]),DDRect([s nativeBounds]),[s scale],[s nativeScale]];
        }
        if(@available(iOS 13.0,*)){
            for(UIScene *scene in [app connectedScenes]){
                [o appendFormat:@"SCENE class=%@ state=%ld role=%@\n",NSStringFromClass([scene class]),(long)[scene activationState],[[scene session] role]];
                if([scene isKindOfClass:[UIWindowScene class]]){
                    UIWindowScene *ws=(UIWindowScene*)scene;
                    [o appendFormat:@" SCENE screen=%@ coordBounds=%@ windows=%lu\n",DDRect([[ws screen] bounds]),DDRect([[ws coordinateSpace] bounds]),(unsigned long)[[ws windows] count]];
                    NSUInteger n=0;
                    for(UIWindow *w in [ws windows]){
                        [o appendFormat:@"  WIN[%lu] class=%@ frame=%@ bounds=%@ safe=%@ hidden=%d level=%.2f root=%@\n",(unsigned long)n++,NSStringFromClass([w class]),DDRect([w frame]),DDRect([w bounds]),DDInsets([w safeAreaInsets]),[w isHidden],[w windowLevel],NSStringFromClass([[w rootViewController] class])];
                        UIView *v=[[w rootViewController] view];
                        if(v) [o appendFormat:@"   ROOTVIEW class=%@ frame=%@ bounds=%@ safe=%@ subviews=%lu\n",NSStringFromClass([v class]),DDRect([v frame]),DDRect([v bounds]),DDInsets([v safeAreaInsets]),(unsigned long)[[v subviews] count]];
                    }
                }
            }
        }
        DDWrite(o);
    });
}

%hook UIWindow
- (void)layoutSubviews {
    %orig;
    static NSTimeInterval last = 0;
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if ((now - last) > 2.0) {
        last = now;
        DDDump();
    }
}
%end

%ctor {
    NSString *p=[[NSProcessInfo processInfo] processName];
    if(![p containsString:@"CarPlay"]) return;
    DDWrite([NSString stringWithFormat:@"\n*** LOGGER LOADED %@ pid=%d ***",[NSDate date],getpid()]);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(2*NSEC_PER_SEC)),dispatch_get_main_queue(),^{ DDDump(); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(8*NSEC_PER_SEC)),dispatch_get_main_queue(),^{ DDDump(); });
}
