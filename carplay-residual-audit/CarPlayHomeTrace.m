// v0.5 INTERMITTENT CarPlay Home / App action triage.
// Off by default. User arms for up to 72 hours; rolling 2x256 KiB logs.
// Calls prior UIKit IMP with unchanged arguments/return; never launches apps.
// Narrow-window interception can have compatibility impact on a jailbroken car.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <fcntl.h>
#import <sys/stat.h>
#import <unistd.h>
#import <time.h>
#import <dispatch/dispatch.h>

static NSString * const kCPAHomeTrace = @"/var/mobile/Documents/CarPlayAudit/CarPlayHomeTouchTrace.log";
static NSString * const kCPAHomeOld = @"/var/mobile/Documents/CarPlayAudit/CarPlayHomeTouchTrace.previous.log";
static NSString * const kCPAHomeArm = @"/var/mobile/Documents/CarPlayAudit/AttributionEnabled";
static const time_t kCPAHomeDuration = 72 * 3600;
static const off_t kCPAHomeMaxSize = 256 * 1024;
static dispatch_queue_t CPAHomeWriter;
static volatile BOOL CPAHomeEnabled = NO;
static time_t CPAHomeExpire = 0;
static int CPAHomeEvents = 0;
static IMP CPAOldHitTest = NULL, CPAOldSendEvent = NULL;
static IMP CPAOldAppAction = NULL, CPAOldControlAction = NULL;

static BOOL CPAHomeActive(void) {
    // NO per-touch stat() or disk I/O; a cheap timer checks STOP/expiry.
    return CPAHomeEnabled && time(NULL) <= CPAHomeExpire;
}
static BOOL CPAHomeArmRecent(time_t *mtimeOut) {
    struct stat s;
    if (stat(kCPAHomeArm.fileSystemRepresentation,&s)!=0) return NO;
    time_t now=time(NULL);
    if (mtimeOut) *mtimeOut = s.st_mtime;
    return now >= s.st_mtime && (now - s.st_mtime) < kCPAHomeDuration;
}
static void CPAHomeWrite(NSString *body) {
    if (!body || !CPAHomeWriter) return;
    int event=__sync_add_and_fetch(&CPAHomeEvents,1);
    NSString *line=[NSString stringWithFormat:@"%.3f pid=%d HOME_TRACE %d %@\n",
                     NSDate.date.timeIntervalSince1970,getpid(),event,body];
    dispatch_async(CPAHomeWriter,^{
        @autoreleasepool {
            int fd=open(kCPAHomeTrace.fileSystemRepresentation,O_WRONLY|O_APPEND|O_CREAT,0644);
            if (fd<0) return;
            struct stat st={0};
            if (fstat(fd,&st)==0 && st.st_size > kCPAHomeMaxSize) {
                close(fd);
                // Bounded disk use: latest 256KiB plus preceding 256KiB.
                unlink(kCPAHomeOld.fileSystemRepresentation);
                rename(kCPAHomeTrace.fileSystemRepresentation,kCPAHomeOld.fileSystemRepresentation);
                fd=open(kCPAHomeTrace.fileSystemRepresentation,O_WRONLY|O_APPEND|O_CREAT,0644);
                if(fd<0) return;
            }
            NSData *data=[line dataUsingEncoding:NSUTF8StringEncoding];
            if(data.length) write(fd,data.bytes,data.length);
            close(fd);
        }
    });
}
static NSString *CPAHomeClass(id value) {
    return value?(NSStringFromClass([value class])?:@"unknown"):@"nil";
}
static NSString *CPAHomeViewPath(UIView *view) {
    if (!view) return @"nil";
    NSMutableArray *parts=[NSMutableArray array];
    for (UIView *node=view;node && parts.count<6;node=node.superview) {
        [parts addObject:[NSString stringWithFormat:@"%@{hidden=%d,alpha=%.2f,interaction=%d,frame=%@}",
         CPAHomeClass(node),node.hidden,node.alpha,node.userInteractionEnabled,
         NSStringFromCGRect(node.frame)]];
    }
    return [parts componentsJoinedByString:@" <- "];
}
static BOOL CPAHomeEligible(UIEvent *ev) {
    if (!ev || ev.type!=UIEventTypeTouches) return NO;
    for (UITouch *t in ev.allTouches?:@[]) {
        if(t.phase==UITouchPhaseBegan || t.phase==UITouchPhaseEnded) return YES;
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
static BOOL CPAHomeDockTouch(CGPoint p) {
    return p.x >= 0 && p.x <= 55 && p.y >= 250;
}
static void CPAHomeSendEvent(UIWindow *win,SEL sel,UIEvent *ev) {
    if (CPAHomeActive() && CPAHomeEligible(ev)) {
        CPAHomeWrite([NSString stringWithFormat:@"WINDOW_SEND_EVENT window=%@ level=%.2f touches=%@",
                      CPAHomeClass(win),win.windowLevel,CPAHomeTouches(ev)]);
    }
    ((void(*)(id,SEL,UIEvent *))CPAOldSendEvent)(win,sel,ev);
}
static UIView *CPAHomeHitTest(UIWindow *win,SEL sel,CGPoint p,UIEvent *ev) {
    UIView *result=((UIView *(*)(id,SEL,CGPoint,UIEvent *))CPAOldHitTest)(win,sel,p,ev);
    if (CPAHomeActive() && CPAHomeEligible(ev)) {
        CPAHomeWrite([NSString stringWithFormat:
          @"HIT_TEST point=%@ dock=%d window=%@ level=%.2f hit=%@ ancestry=%@",
          NSStringFromCGPoint(p),CPAHomeDockTouch(p),CPAHomeClass(win),win.windowLevel,
          CPAHomeClass(result),CPAHomeViewPath(result)]);
    }
    return result;
}
static BOOL CPAHomeAppAction(UIApplication *obj,SEL sel,SEL action,id target,id sender,UIEvent *ev) {
    if(CPAHomeActive()) CPAHomeWrite([NSString stringWithFormat:
       @"APP_SEND_ACTION action=%@ target=%@ sender=%@",
       NSStringFromSelector(action),CPAHomeClass(target),CPAHomeClass(sender)]);
    return ((BOOL(*)(id,SEL,SEL,id,id,UIEvent *))CPAOldAppAction)(obj,sel,action,target,sender,ev);
}
static void CPAHomeControlAction(UIControl *obj,SEL sel,SEL action,id target,UIEvent *ev) {
    if(CPAHomeActive()) CPAHomeWrite([NSString stringWithFormat:
      @"CONTROL_SEND_ACTION control=%@ action=%@ target=%@",
      CPAHomeClass(obj),NSStringFromSelector(action),CPAHomeClass(target)]);
    ((void(*)(id,SEL,SEL,id,UIEvent *))CPAOldControlAction)(obj,sel,action,target,ev);
}
static void CPAHomeInstall(Class cls,SEL sel,IMP impl,IMP *old) {
    if(!cls || !sel || !old)return;
    Method method=class_getInstanceMethod(cls,sel);
    if(!method) {
        CPAHomeWrite([NSString stringWithFormat:@"METHOD_MISSING %@ %@",NSStringFromClass(cls),NSStringFromSelector(sel)]);
        return;
    }
    IMP existing=method_getImplementation(method);
    if(!existing || existing==impl)return;
    const char *types=method_getTypeEncoding(method);
    if(class_addMethod(cls,sel,impl,types)) *old=existing;
    else *old=method_setImplementation(class_getInstanceMethod(cls,sel),impl);
    if(!*old)return;
    Dl_info info={0};
    dladdr((void*)*old,&info);
    CPAHomeWrite([NSString stringWithFormat:@"HOOK_HOME class=%@ method=%@ priorImage=%s",
        NSStringFromClass(cls),NSStringFromSelector(sel),info.dli_fname?: "unavailable"]);
}
__attribute__((constructor)) static void CPAStartHomeTrace(void) {
    @autoreleasepool {
        NSString *proc=NSProcessInfo.processInfo.processName.lowercaseString;
        if(![proc containsString:@"carplay"])return;
        time_t armedAt=0;
        if(!CPAHomeArmRecent(&armedAt))return;
        CPAHomeWriter=dispatch_queue_create("com.chuong.carplayaudit.home.rolling",DISPATCH_QUEUE_SERIAL);
        CPAHomeExpire=armedAt+kCPAHomeDuration;
        CPAHomeEnabled=YES;
        CPAHomeWrite([NSString stringWithFormat:@"TRACE_STARTED v0.5 intermittent, rolling 2x256KiB, armed=%lld until=%lld",
                      (long long)armedAt,(long long)CPAHomeExpire]);
        CPAHomeInstall([UIWindow class],@selector(sendEvent:),(IMP)CPAHomeSendEvent,&CPAOldSendEvent);
        CPAHomeInstall([UIWindow class],@selector(hitTest:withEvent:),(IMP)CPAHomeHitTest,&CPAOldHitTest);
        CPAHomeInstall([UIApplication class],@selector(sendAction:to:from:forEvent:),
                       (IMP)CPAHomeAppAction,&CPAOldAppAction);
        CPAHomeInstall([UIControl class],@selector(sendAction:to:forEvent:),
                       (IMP)CPAHomeControlAction,&CPAOldControlAction);
        CPAHomeWrite(@"HOOKS_READY; events are evidence of UIKit routing, not scene-activation ACK");
        dispatch_async(dispatch_get_main_queue(), ^{
            __block dispatch_source_t timer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
            if(!timer)return;
            dispatch_source_set_timer(timer,dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_SEC),
                                     10*NSEC_PER_SEC,NSEC_PER_SEC);
            dispatch_source_set_event_handler(timer,^{
                // Poll file 1/10s rather than on each touch. STOP from app removes marker.
                struct stat st={0};
                BOOL present=stat(kCPAHomeArm.fileSystemRepresentation,&st)==0;
                if(!present || st.st_mtime!=armedAt || time(NULL)>CPAHomeExpire) {
                    CPAHomeEnabled=NO;
                    CPAHomeWrite(@"TRACE_FINISHED arm removed/changed or 72-hour expiry");
                    dispatch_source_cancel(timer);
                    timer=nil;
                }
            });
            dispatch_resume(timer);
        });
    }
}
