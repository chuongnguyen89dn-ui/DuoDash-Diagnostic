#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

static NSString *DDPath(void) { return @"/var/mobile/Documents/DuoDash-geometry-live.txt"; }

static NSString *DDRect(CGRect r) {
    return [NSString stringWithFormat:@"{{%.2f,%.2f},{%.2f,%.2f}}", r.origin.x,r.origin.y,r.size.width,r.size.height];
}
static NSString *DDInsets(UIEdgeInsets i) {
    return [NSString stringWithFormat:@"{%.2f,%.2f,%.2f,%.2f}",i.top,i.left,i.bottom,i.right];
}
static void DDWrite(NSString *s) {
    NSFileHandle *h=[NSFileHandle fileHandleForWritingAtPath:DDPath()];
    if(!h){ [@"" writeToFile:DDPath() atomically:YES encoding:NSUTF8StringEncoding error:nil]; h=[NSFileHandle fileHandleForWritingAtPath:DDPath()]; }
    [h seekToEndOfFile];
    [h writeData:[[s stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding]];
    [h closeFile];
}
static void DDDump(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIApplication *app=UIApplication.sharedApplication;
        NSMutableString *o=[NSMutableString stringWithFormat:@"\n=== %@ process=%@ ===\n",[NSDate date],NSProcessInfo.processInfo.processName];
        NSArray<UIScreen*> *screens=UIScreen.screens;
        [o appendFormat:@"screens=%lu\n",(unsigned long)screens.count];
        for(NSUInteger i=0;i<screens.count;i++){
            UIScreen *s=screens[i];
            [o appendFormat:@"SCREEN[%lu] bounds=%@ nativeBounds=%@ scale=%.3f nativeScale=%.3f\n",(unsigned long)i,DDRect(s.bounds),DDRect(s.nativeBounds),s.scale,s.nativeScale];
        }
        NSMutableArray<UIWindow*> *wins=[NSMutableArray array];\n        if(@available(iOS 13.0,*)){ for(UIScene *scene in app.connectedScenes) if([scene isKindOfClass:UIWindowScene.class]) [wins addObjectsFromArray:((UIWindowScene*)scene).windows]; }
        [o appendFormat:@"windows=%lu\n",(unsigned long)wins.count];
        for(NSUInteger i=0;i<wins.count;i++){
            UIWindow *w=wins[i];
            [o appendFormat:@"WIN[%lu] class=%@ screen=%@ frame=%@ bounds=%@ safe=%@ hidden=%d level=%.2f root=%@\n",(unsigned long)i,NSStringFromClass(w.class),DDRect(w.screen.bounds),DDRect(w.frame),DDRect(w.bounds),DDInsets(w.safeAreaInsets),w.hidden,w.windowLevel,NSStringFromClass(w.rootViewController.class)];
            UIView *v=w.rootViewController.view;
            if(v) [o appendFormat:@" ROOTVIEW frame=%@ bounds=%@ safe=%@\n",DDRect(v.frame),DDRect(v.bounds),DDInsets(v.safeAreaInsets)];
        }
        if(@available(iOS 13.0,*)){
            for(UIScene *scene in app.connectedScenes){
                [o appendFormat:@"SCENE class=%@ state=%ld role=%@\n",NSStringFromClass(scene.class),(long)scene.activationState,scene.session.role];
                if([scene isKindOfClass:UIWindowScene.class]){
                    UIWindowScene *ws=(UIWindowScene*)scene;
                    [o appendFormat:@" SCENE screen=%@ coordBounds=%@ windows=%lu\n",DDRect(ws.screen.bounds),DDRect(ws.coordinateSpace.bounds),(unsigned long)ws.windows.count];
                    for(UIWindow *w in ws.windows)
                        [o appendFormat:@"  SWIN class=%@ frame=%@ bounds=%@ safe=%@ root=%@\n",NSStringFromClass(w.class),DDRect(w.frame),DDRect(w.bounds),DDInsets(w.safeAreaInsets),NSStringFromClass(w.rootViewController.class)];
                }
            }
        }
        DDWrite(o);
    });
}

%hook UIWindow
- (void)layoutSubviews { %orig; static NSTimeInterval last=0; NSTimeInterval now=NSDate.date.timeIntervalSince1970; if(now-last>2){last=now; DDDump();} }
%end

%ctor {
    if(![NSProcessInfo.processInfo.processName containsString:@"CarPlay"]) return;
    DDWrite([NSString stringWithFormat:@"\n*** LOGGER LOADED %@ pid=%d ***",[NSDate date],getpid()]);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2*NSEC_PER_SEC),dispatch_get_main_queue(),^{ DDDump(); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 8*NSEC_PER_SEC),dispatch_get_main_queue(),^{ DDDump(); });
}
