// 0.4 CarPlay HOME / app-switch triage.
// Opt-in five-minute, bounded, original-IMP-preserving observation.
// No simulated taps, CarPlay activation, geometry modification or app termination.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <fcntl.h>
#import <sys/stat.h>
#import <unistd.h>
#import <time.h>
#import <dispatch/dispatch.h>

static NSString * const kCPAHomeTrace=@"/var/mobile/Documents/CarPlayAudit/CarPlayHomeTouchTrace.log";
static NSString * const kCPAHomeArm=@"/var/mobile/Documents/CarPlayAudit/AttributionEnabled";
static dispatch_queue_t CPAHomeWriter;
static BOOL CPAHomeEnabled = NO;
static time_t CPAHomeExpire = 0;
static int CPAHomeEvents = 0;
static IMP CPAOldHitTest = NULL, CPAOldSendEvent = NULL;
static IMP CPAOldAppAction = NULL, CPAOldControlAction = NULL;

static BOOL CPAHomeActive(void) {
    if (!CPAHomeEnabled || time(NULL)>CPAHomeExpire || CPAHomeEvents>=320) return NO;
    struct stat s;
    return stat(kCPAHomeArm.fileSystemRepresentation,&s)==0;
}
static BOOL CPAHomeArmRecent(void) {
    struct stat s;
    if (stat(kCPAHomeArm.fileSystemRepresentation,&s)!=0) return NO;
    time_t now=time(NULL);
    return now>=s.st_mtime && now-s.st_mtime<300;
}
static void CPAHomeWrite(NSString *body) {
    if (!body || !CPAHomeWriter) return;
    int event=__sync_add_and_fetch(&CPAHomeEvents,1);
    if (event>320) return;
    NSString *line=[NSString stringWithFormat:@"%.3f pid=%d HOME_TRACE %03d %@\n",
        NSDate.date.timeIntervalSince1970,getpid(),event,body];
    dispatch_async(CPAHomeWriter,^{
        int fd=open(kCPAHomeTrace.fileSystemRepresentation,O_WRONLY|O_APPEND|O_CREAT,0644);
        if(fd<0)return;
        NSData *d=[line dataUsingEncoding:NSUTF8StringEncoding];
        if(d.length)write(fd,d.bytes,d.length);
        close(fd);
    });
}
static NSString *CPAHomeClass(id value) {
    if (!value) return @"nil";
    return NSStringFromClass([value class])?:@"unknown";
}
static NSString *CPAHomeName(UIView *view) {
    if (!view) return @"nil";
    NSMutableArray *parts=[NSMutableArray array];
    for (UIView *node=view;node && parts.count<7;node=node.superview) {
        [parts addObject:[NSString stringWithFormat:@"%@{hidden=%d,alpha=%.2f,userInteraction=%d,frame=%@}",
             CPAHomeClass(node),node.hidden,node.alpha,node.userInteractionEnabled,
             NSStringFromCGRect(node.frame)]];
    }
    return [parts componentsJoinedByString:@" <- "];
}
static BOOL CPAHomeEligible(UIEvent *ev) {
    if (!ev || ev.type!=UIEventTypeTouches) return NO;
    for (UITouch *t in ev.allTouches ?: @[]) {
        if (t.phase==UITouchPhaseBegan || t.phase==UITouchPhaseEnded) return YES;
    }
    return NO;
}
static NSString *CPAHomeTouches(UIEvent *ev) {
    NSMutableArray *items=[NSMutableArray array];
    for (UITouch *t in ev.allTouches?:@[]) {
        if (t.phase!=UITouchPhaseBegan && t.phase!=UITouchPhaseEnded) continue;
        CGPoint p=[t locationInView:t.window];
        [items addObject:[NSString stringWithFormat:@"phase=%ld pos=%@ touchView=%@",
          (long)t.phase,NSStringFromCGPoint(p),CPAHomeClass(t.view)]];
    }
    return [items componentsJoinedByString:@";"];
}
static void CPAHomeSendEvent(UIWindow *win,SEL sel,UIEvent *ev) {
    if (CPAHomeActive() && CPAHomeEligible(ev)) {
        CPAHomeWrite([NSString stringWithFormat:@"WINDOW_SEND_EVENT window=%@ level=%0.2f touches=%@",
              CPAHomeClass(win),win.windowLevel,CPAHomeTouches(ev)]);
    }
    ((void(*)(id,SEL,UIEvent *))CPAOldSendEvent)(win,sel,ev);
}
static UIView *CPAHomeHitTest(UIWindow *win,SEL sel,CGPoint point,UIEvent *ev) {
    UIView *result=((UIView *(*)(id,SEL,CGPoint,UIEvent *))CPAOldHitTest)(win,sel,point,ev);
    if (CPAHomeActive() && CPAHomeEligible(ev)) {
        // Scope: lower-left dock Home button plus user interactions elsewhere
        // on the CarPlay dashboard. Do not call hitTest twice.
        CPAHomeWrite([NSString stringWithFormat:
             @"HIT_TEST point=%@ dockRegion=%d window=%@ windowLevel=%0.2f hit=%@ ancestry=%@",
             NSStringFromCGPoint(point),(point.x<=55 && point.y>=280),
             CPAHomeClass(win),win.windowLevel,CPAHomeClass(result),CPAHomeName(result)]);
    }
    return result;
}
static BOOL CPAHomeAppAction(UIApplication *obj,SEL sel,SEL action,id target,id sender,UIEvent *event) {
    if(CPAHomeActive())CPAHomeWrite([NSString stringWithFormat:
      @"APP_SEND_ACTION action=%@ target=%@ sender=%@ touches=%@",
      NSStringFromSelector(action),CPAHomeClass(target),CPAHomeClass(sender),
      event?CPAHomeTouches(event):@"none"]);
    return ((BOOL(*)(id,SEL,SEL,id,id,UIEvent *))CPAOldAppAction)(obj,sel,action,target,sender,event);
}
static void CPAHomeControlAction(UIControl *obj,SEL sel,SEL action,id target,UIEvent *event) {
    if(CPAHomeActive())CPAHomeWrite([NSString stringWithFormat:
      @"CONTROL_SEND_ACTION control=%@ action=%@ target=%@ touches=%@",
      CPAHomeClass(obj),NSStringFromSelector(action),CPAHomeClass(target),
      event?CPAHomeTouches(event):@"none"]);
    ((void(*)(id,SEL,SEL,id,UIEvent *))CPAOldControlAction)(obj,sel,action,target,event);
}
static void CPAHomeInstall(Class cls,SEL sel,IMP impl,IMP *old) {
    if (!cls || !sel) return;
    Method method=class_getInstanceMethod(cls,sel);
    if(!method) {
        CPAHomeWrite([NSString stringWithFormat:@"MISSING_METHOD %@ %@",
          NSStringFromClass(cls),NSStringFromSelector(sel)]);
        return;
    }
    IMP existing=method_getImplementation(method);
    if(!existing || existing==impl) return;
    const char *encoding=method_getTypeEncoding(method);
    if(class_addMethod(cls,sel,impl,encoding)) *old=existing;
    else *old=method_setImplementation(class_getInstanceMethod(cls,sel),impl);
    if (!*old) return;
    Dl_info info={0};dladdr((void *)*old,&info);
    CPAHomeWrite([NSString stringWithFormat:@"HOOK_HOME %@ %@ priorImage=%s",
       NSStringFromClass(cls),NSStringFromSelector(sel),
       info.dli_fname?: "unavailable"]);
}
__attribute__((constructor)) static void CPAStartHomeTrace(void) {
    @autoreleasepool {
        NSString *proc=NSProcessInfo.processInfo.processName.lowercaseString;
        if (![proc containsString:@"carplay"] || !CPAHomeArmRecent()) return;
        CPAHomeWriter=dispatch_queue_create("com.chuong.carplayaudit.home.trace",DISPATCH_QUEUE_SERIAL);
        CPAHomeEnabled=YES;CPAHomeExpire=time(NULL)+300;
        CPAHomeWrite(@"TRACE_STARTED v0.4 (touch delivery, hitTest, target-action only)");
        CPAHomeInstall([UIWindow class],@selector(sendEvent:),(IMP)CPAHomeSendEvent,&CPAOldSendEvent);
        CPAHomeInstall([UIWindow class],@selector(hitTest:withEvent:),(IMP)CPAHomeHitTest,&CPAOldHitTest);
        CPAHomeInstall([UIApplication class],@selector(sendAction:to:from:forEvent:),
                        (IMP)CPAHomeAppAction,&CPAOldAppAction);
        CPAHomeInstall([UIControl class],@selector(sendAction:to:forEvent:),
                        (IMP)CPAHomeControlAction,&CPAOldControlAction);
        CPAHomeWrite(@"HOOKS_READY; absence of touch events cannot by itself prove blocking in CarPlay");
        dispatch_async(dispatch_get_main_queue(), ^{
            __block dispatch_source_t timer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
            if(!timer)return;
            dispatch_source_set_timer(timer,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),
                        2*NSEC_PER_SEC,NSEC_PER_SEC/2);
            dispatch_source_set_event_handler(timer,^{
                if(!CPAHomeActive()) {
                    CPAHomeEnabled=NO;
                    CPAHomeWrite(@"TRACE_FINISHED");
                    dispatch_source_cancel(timer);
                }
            });
            dispatch_resume(timer);
        });
    }
}
