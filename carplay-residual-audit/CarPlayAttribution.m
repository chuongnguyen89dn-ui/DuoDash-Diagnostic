// Opt-in, bounded, read-only caller attribution. NO geometry mutation.
// Installed in CarPlay only when the user arms it before CarPlay process starts.
// Original IMP is ALWAYS called, with same argument and return ABI.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <execinfo.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>
#import <time.h>
#import <math.h>
#import <string.h>

static NSString * const kCPAArm = @"/var/mobile/Documents/CarPlayAudit/AttributionEnabled";
static NSString * const kCPATrace = @"/var/mobile/Documents/CarPlayAudit/CarPlayAttributionTrace.log";
static BOOL gCPAArmed = NO;
static time_t gCPAUntil = 0;
static int gCPAEvents = 0;
static dispatch_queue_t gCPAWriter;
static IMP gUIViewFrame = NULL, gUIWindowFrame = NULL, gDBAnimationFrame = NULL;
static IMP gUIViewBounds = NULL, gUIWindowBounds = NULL, gDBAnimationBounds = NULL;
static IMP gSafeChanged = NULL, gAdditionalSafe = NULL;

static void CPAWriteTrace(NSString *text) {
    if (!text.length || !gCPAWriter) return;
    NSString *line = [NSString stringWithFormat:@"%.3f pid=%d %@\n",
                      NSDate.date.timeIntervalSince1970, getpid(), text];
    dispatch_async(gCPAWriter, ^{
        @autoreleasepool {
            int fd=open(kCPATrace.fileSystemRepresentation,O_WRONLY|O_CREAT|O_APPEND,0644);
            if (fd<0) return;
            NSData *data=[line dataUsingEncoding:NSUTF8StringEncoding];
            if (data.length) write(fd,data.bytes,data.length);
            close(fd);
        }
    });
}
static BOOL CPAEnabled(void) {
    return gCPAArmed && time(NULL)<=gCPAUntil && gCPAEvents<240;
}
static BOOL CPATarget(id obj) {
    if (!obj) return NO;
    if ([obj isKindOfClass:[UIWindow class]]) return YES;
    NSString *cn=NSStringFromClass([obj class]);
    return [cn containsString:@"DBAnimation"] || [cn containsString:@"DBApplication"] ||
           [cn containsString:@"DBDock"] || [cn containsString:@"CARApplication"] ||
           [cn containsString:@"DBStatusBar"] || [cn containsString:@"CornerRadius"];
}
static NSString *CPACallerStack(void) {
    void *stack[12]={0};
    int n=backtrace(stack,12);
    NSMutableArray *items=[NSMutableArray array];
    for (int i=2;i<n && items.count<6;i++) {
        Dl_info info={0};
        if (dladdr(stack[i],&info) && info.dli_fname) {
            const char *filename=strrchr(info.dli_fname,'/');
            NSString *module=[NSString stringWithUTF8String:filename ? filename+1 : info.dli_fname];
            NSString *symbol=info.dli_sname ? [NSString stringWithUTF8String:info.dli_sname] : @"?";
            [items addObject:[NSString stringWithFormat:@"%@:%@", module ?: @"?",symbol ?: @"?"]];
        }
    }
    return [items componentsJoinedByString:@" > "];
}
static BOOL CPADifferentRect(CGRect a,CGRect b) {
    return fabs(a.origin.x-b.origin.x)>0.2 || fabs(a.origin.y-b.origin.y)>0.2 ||
           fabs(a.size.width-b.size.width)>0.2 || fabs(a.size.height-b.size.height)>0.2;
}
static void CPALogGeometry(id obj, NSString *method,CGRect before,CGRect after,
                           NSString *caller) {
    if (!CPAEnabled() || !CPATarget(obj) || !CPADifferentRect(before,after)) return;
    int count=__sync_add_and_fetch(&gCPAEvents,1);
    if (count>240) return;
    CPAWriteTrace([NSString stringWithFormat:
        @"CALLER_GEOMETRY event=%d class=%@ method=%@ before=%@ after=%@ stack=%@",
        count,NSStringFromClass([obj class]),method,NSStringFromCGRect(before),
        NSStringFromCGRect(after),caller]);
}
static void CPAFrameUIView(id obj,SEL sel,CGRect value) {
    CGRect prev=[obj frame];
    BOOL candidate=CPAEnabled() && CPATarget(obj);
    NSString *caller=candidate?CPACallerStack():nil;
    ((void(*)(id,SEL,CGRect))gUIViewFrame)(obj,sel,value);
    if (candidate) CPALogGeometry(obj,@"setFrame:",prev,[obj frame],caller);
}
static void CPAFrameUIWindow(id obj,SEL sel,CGRect value) {
    CGRect prev=[obj frame];
    BOOL candidate=CPAEnabled() && CPATarget(obj);
    NSString *caller=candidate?CPACallerStack():nil;
    ((void(*)(id,SEL,CGRect))gUIWindowFrame)(obj,sel,value);
    if (candidate) CPALogGeometry(obj,@"setFrame:",prev,[obj frame],caller);
}
static void CPAFrameDBAnimation(id obj,SEL sel,CGRect value) {
    CGRect prev=[obj frame];
    BOOL candidate=CPAEnabled() && CPATarget(obj);
    NSString *caller=candidate?CPACallerStack():nil;
    ((void(*)(id,SEL,CGRect))gDBAnimationFrame)(obj,sel,value);
    if (candidate) CPALogGeometry(obj,@"setFrame:",prev,[obj frame],caller);
}
static void CPABoundsUIView(id obj,SEL sel,CGRect value) {
    CGRect prev=[obj bounds];
    BOOL candidate=CPAEnabled() && CPATarget(obj);
    NSString *caller=candidate?CPACallerStack():nil;
    ((void(*)(id,SEL,CGRect))gUIViewBounds)(obj,sel,value);
    if (candidate) CPALogGeometry(obj,@"setBounds:",prev,[obj bounds],caller);
}
static void CPABoundsUIWindow(id obj,SEL sel,CGRect value) {
    CGRect prev=[obj bounds];
    BOOL candidate=CPAEnabled() && CPATarget(obj);
    NSString *caller=candidate?CPACallerStack():nil;
    ((void(*)(id,SEL,CGRect))gUIWindowBounds)(obj,sel,value);
    if (candidate) CPALogGeometry(obj,@"setBounds:",prev,[obj bounds],caller);
}
static void CPABoundsDBAnimation(id obj,SEL sel,CGRect value) {
    CGRect prev=[obj bounds];
    BOOL candidate=CPAEnabled() && CPATarget(obj);
    NSString *caller=candidate?CPACallerStack():nil;
    ((void(*)(id,SEL,CGRect))gDBAnimationBounds)(obj,sel,value);
    if (candidate) CPALogGeometry(obj,@"setBounds:",prev,[obj bounds],caller);
}
static void CPASafeInsetsDidChange(id obj,SEL sel) {
    BOOL candidate=CPAEnabled() && CPATarget(obj);
    NSString *caller=candidate?CPACallerStack():nil;
    ((void(*)(id,SEL))gSafeChanged)(obj,sel);
    if (!candidate || !CPAEnabled()) return;
    int n=__sync_add_and_fetch(&gCPAEvents,1);
    if (n>240) return;
    UIView *view=obj;
    CPAWriteTrace([NSString stringWithFormat:
        @"SAFEAREA_NOTIFICATION event=%d class=%@ current=%@ stack=%@",
        n,NSStringFromClass([obj class]),NSStringFromUIEdgeInsets(view.safeAreaInsets),caller]);
}
static void CPASetAdditionalSafe(id obj,SEL sel,UIEdgeInsets value) {
    UIViewController *vc=obj;
    UIEdgeInsets prev=vc.additionalSafeAreaInsets;
    BOOL candidate=CPAEnabled();
    NSString *caller=candidate?CPACallerStack():nil;
    ((void(*)(id,SEL,UIEdgeInsets))gAdditionalSafe)(obj,sel,value);
    if (!candidate || !CPAEnabled()) return;
    if (UIEdgeInsetsEqualToEdgeInsets(prev,vc.additionalSafeAreaInsets)) return;
    int n=__sync_add_and_fetch(&gCPAEvents,1);
    if (n>240) return;
    CPAWriteTrace([NSString stringWithFormat:
        @"EXPLICIT_ADDITIONAL_SAFEAREA event=%d class=%@ before=%@ after=%@ stack=%@",
        n,NSStringFromClass([obj class]),NSStringFromUIEdgeInsets(prev),
        NSStringFromUIEdgeInsets(vc.additionalSafeAreaInsets),caller]);
}
static BOOL CPAHookClass(Class cls,SEL sel,IMP replacement,IMP *original) {
    if (!cls || !replacement || !original) return NO;
    Method method=class_getInstanceMethod(cls,sel);
    if (!method) return NO;
    IMP before=method_getImplementation(method);
    if (!before || before==replacement) return NO;
    const char *types=method_getTypeEncoding(method);
    if (class_addMethod(cls,sel,replacement,types)) {
        *original=before; // Own override of an inherited method.
    } else {
        // Must retrieve method from this class ONLY after addMethod failed.
        Method own=class_getInstanceMethod(cls,sel);
        *original=method_setImplementation(own,replacement);
    }
    Dl_info prevInfo={0};
    dladdr((void *)*original,&prevInfo);
    CPAWriteTrace([NSString stringWithFormat:@"HOOK_CHAIN class=%@ method=%@ previous=%s",
        NSStringFromClass(cls),NSStringFromSelector(sel),prevInfo.dli_fname?: "unknown"]);
    return YES;
}
static BOOL CPAArmIsFresh(void) {
    struct stat s;
    if (stat(kCPAArm.fileSystemRepresentation,&s)!=0) return NO;
    return difftime(time(NULL),s.st_mtime)>=0 && difftime(time(NULL),s.st_mtime)<300;
}
__attribute__((constructor))
static void CPAInstallAttribution(void) {
    @autoreleasepool {
        NSString *proc=NSProcessInfo.processInfo.processName.lowercaseString;
        if (![proc containsString:@"carplay"]) return;
        if (!CPAArmIsFresh()) return; // OFF by default and requires deliberate tap.
        gCPAWriter=dispatch_queue_create("com.chuong.carplayaudit.attribution",DISPATCH_QUEUE_SERIAL);
        gCPAArmed=YES;
        gCPAUntil=time(NULL)+300;
        CPAWriteTrace(@"TRACE_BEGIN v0.3 read-only five-minute bounded probe");
        Class animation=objc_getClass("DBAnimationView");
        CPAHookClass([UIView class],@selector(setFrame:),(IMP)CPAFrameUIView,&gUIViewFrame);
        CPAHookClass([UIWindow class],@selector(setFrame:),(IMP)CPAFrameUIWindow,&gUIWindowFrame);
        CPAHookClass(animation,@selector(setFrame:),(IMP)CPAFrameDBAnimation,&gDBAnimationFrame);
        CPAHookClass([UIView class],@selector(setBounds:),(IMP)CPABoundsUIView,&gUIViewBounds);
        CPAHookClass([UIWindow class],@selector(setBounds:),(IMP)CPABoundsUIWindow,&gUIWindowBounds);
        CPAHookClass(animation,@selector(setBounds:),(IMP)CPABoundsDBAnimation,&gDBAnimationBounds);
        CPAHookClass([UIView class],@selector(safeAreaInsetsDidChange),
                     (IMP)CPASafeInsetsDidChange,&gSafeChanged);
        CPAHookClass([UIViewController class],@selector(setAdditionalSafeAreaInsets:),
                     (IMP)CPASetAdditionalSafe,&gAdditionalSafe);
        CPAWriteTrace(@"TRACE_HOOKS_INSTALLED: calls preserve original args; caller stack is observation, not proof of cause");
        dispatch_async(dispatch_get_main_queue(), ^{
            dispatch_source_t timer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
            if (!timer) return;
            dispatch_source_set_timer(timer,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),
                    2*NSEC_PER_SEC,NSEC_PER_SEC/2);
            dispatch_source_set_event_handler(timer,^{
                if (gCPAArmed && (!CPAArmIsFresh() || time(NULL)>gCPAUntil ||
                    gCPAEvents>=240)) {
                    gCPAArmed=NO;
                    CPAWriteTrace(@"TRACE_END expired / user stopped / event cap");
                    dispatch_source_cancel(timer);
                }
            });
            dispatch_resume(timer);
            // GCD source retains itself while scheduled; cancellation releases via handler.
        });
    }
}
