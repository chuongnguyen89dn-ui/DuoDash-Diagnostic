// Read-only runtime audit. No Logos hooks and no modifications to geometry/events.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>
#import <time.h>
#import <string.h>
#import <dispatch/dispatch.h>

static dispatch_queue_t CPALogQueue;
static NSString * const kProbeDirectory = @"/var/mobile/Documents/CarPlayAudit";
static NSString * const kProbePath = @"/var/mobile/Documents/CarPlayAudit/CarPlayRuntimeProbe.log";

static BOOL CPAInteresting(const char *s) {
    if (!s) return NO;
    NSString *value = [[NSString stringWithUTF8String:s] lowercaseString];
    NSArray *tokens = @[@"duodash", @"airaw", @"carbridge", @"geometryfix", @"carnav",
        @"carplaydsp", @"duoface", @"duonavi", @"omnicar", @"sideplay", @"gmaphud",
        @"ellekit", @"tweak", @"substrate", @"libhooker", @"carwebview"];
    for (NSString *token in tokens) if ([value containsString:token]) return YES;
    return NO;
}
static void CPAAppendFile(NSString *event) {
    @autoreleasepool {
        [[NSFileManager defaultManager] createDirectoryAtPath:kProbeDirectory
                                  withIntermediateDirectories:YES attributes:nil error:nil];
        int fd = open(kProbePath.fileSystemRepresentation, O_WRONLY|O_CREAT|O_APPEND, 0644);
        if (fd < 0) return;
        NSString *line = [NSString stringWithFormat:@"%.0f pid=%d process=%@ %@\n",
                          NSDate.date.timeIntervalSince1970, getpid(),
                          NSProcessInfo.processInfo.processName, event];
        NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
        write(fd, data.bytes, data.length);
        close(fd);
    }
}
static void CPAImageDidLoad(const struct mach_header *mh, intptr_t slide) {
    (void)slide;
    if (!CPALogQueue) return;
    uint32_t count = _dyld_image_count();
    for (uint32_t i=0; i<count; i++) {
        if (_dyld_get_image_header(i) != mh) continue;
        const char *name = _dyld_get_image_name(i);
        if (!name) return;
        // Collect every third-party injected module; exclude Apple system binaries
        // unless they directly match a named CarPlay/tweak investigation target.
        BOOL thirdParty = strstr(name,"/var/jb/") || strstr(name,"/Library/MobileSubstrate/") ||
                          strstr(name,"/TweakInject/");
        if (!thirdParty && !CPAInteresting(name)) return;
        NSString *path = [NSString stringWithUTF8String:name];
        if (!path) return;
        dispatch_async(CPALogQueue, ^{
            CPAAppendFile([NSString stringWithFormat:@"DYLD_IMAGE %@",path]);
        });
        return;
    }
}

// Passive main-thread geometry snapshots: no method swizzling, no frame/safe-area writes.
static dispatch_source_t CPAGeometryTimer;
static void CPAGeometryView(UIView *view, NSUInteger depth, NSUInteger *count) {
    if (!view || !count || *count >= 18 || depth > 2) return;
    (*count)++;
    NSString *event = [NSString stringWithFormat:
        @"GEOMETRY_VIEW depth=%lu class=%@ frame=%@ bounds=%@ safe=%@ hidden=%d alpha=%.2f",
        (unsigned long)depth, NSStringFromClass(view.class),
        NSStringFromCGRect(view.frame), NSStringFromCGRect(view.bounds),
        NSStringFromUIEdgeInsets(view.safeAreaInsets), view.hidden, view.alpha];
    dispatch_async(CPALogQueue, ^{ CPAAppendFile(event); });
    for (UIView *child in view.subviews) {
        if (*count >= 18) break;
        CPAGeometryView(child, depth+1, count);
    }
}
static void CPAGeometrySnapshot(NSUInteger cycle) {
    UIApplication *app = UIApplication.sharedApplication;
    NSMutableArray<UIWindow *> *windows = [NSMutableArray arrayWithArray:app.windows ?: @[]];
    for (UIScene *scene in app.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows)
            if (![windows containsObject:window]) [windows addObject:window];
    }
    dispatch_async(CPALogQueue, ^{
        CPAAppendFile([NSString stringWithFormat:
            @"GEOMETRY_SNAPSHOT cycle=%lu windows=%lu",
            (unsigned long)cycle,(unsigned long)windows.count]);
    });
    NSUInteger index = 0;
    for (UIWindow *window in windows) {
        if (index++ >= 10) break;
        NSString *event = [NSString stringWithFormat:
            @"GEOMETRY_WINDOW index=%lu class=%@ frame=%@ bounds=%@ safe=%@ screen=%@ level=%.1f hidden=%d root=%@",
            (unsigned long)(index-1),NSStringFromClass(window.class),
            NSStringFromCGRect(window.frame),NSStringFromCGRect(window.bounds),
            NSStringFromUIEdgeInsets(window.safeAreaInsets),
            NSStringFromCGRect(window.screen.bounds), window.windowLevel, window.hidden,
            window.rootViewController ? NSStringFromClass(window.rootViewController.class) : @"none"];
        dispatch_async(CPALogQueue, ^{ CPAAppendFile(event); });
        NSUInteger count=0;
        CPAGeometryView(window.rootViewController.view ?: window,0,&count);
    }
}
static void CPAScheduleGeometrySamples(void) {
    NSString *name = NSProcessInfo.processInfo.processName.lowercaseString;
    if (![name containsString:@"carplay"] && ![name containsString:@"dashboard"]) return;
    CPAGeometryTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
    if (!CPAGeometryTimer) return;
    dispatch_source_set_timer(CPAGeometryTimer,
      dispatch_time(DISPATCH_TIME_NOW,(int64_t)(3*NSEC_PER_SEC)),
      (uint64_t)(5*NSEC_PER_SEC),(uint64_t)(NSEC_PER_SEC));
    __block NSUInteger cycle=0;
    dispatch_source_set_event_handler(CPAGeometryTimer, ^{
        @try { CPAGeometrySnapshot(++cycle); }
        @catch (NSException *exception) {
            dispatch_async(CPALogQueue, ^{
                CPAAppendFile([NSString stringWithFormat:@"GEOMETRY_UNAVAILABLE %@",exception.name]);
            });
        }
        if (cycle>=90) dispatch_source_cancel(CPAGeometryTimer);
    });
    dispatch_resume(CPAGeometryTimer);
}

__attribute__((constructor))
static void CPAProbeStart(void) {
    @autoreleasepool {
        CPALogQueue = dispatch_queue_create("com.chuong.carplayaudit.log", DISPATCH_QUEUE_SERIAL);
        dispatch_async(CPALogQueue, ^{
            CPAAppendFile(@"PROBE_LOADED injection=yes version=0.2");
            CPAAppendFile([NSString stringWithFormat:@"BUNDLE_ID %@",
                  NSBundle.mainBundle.bundleIdentifier ?: @"(none)"]);
        });
        _dyld_register_func_for_add_image(CPAImageDidLoad);
        dispatch_async(dispatch_get_main_queue(), ^{ CPAScheduleGeometrySamples(); });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4*NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            @try {
                NSMutableArray *screens = [NSMutableArray array];
                for (UIScreen *screen in UIScreen.screens) {
                    [screens addObject:[NSString stringWithFormat:
                        @"screen=%@ bounds=%@ nativeBounds=%@ scale=%.2f",
                        screen,NSStringFromCGRect(screen.bounds),
                        NSStringFromCGRect(screen.nativeBounds),screen.scale]];
                }
                dispatch_async(CPALogQueue, ^{
                    CPAAppendFile([NSString stringWithFormat:@"SCREEN_SNAPSHOT %@",screens]);
                });
            } @catch (NSException *exception) {
                dispatch_async(CPALogQueue, ^{
                    CPAAppendFile([NSString stringWithFormat:@"SCREEN_UNAVAILABLE %@",exception.name]);
                });
            }
        });
    }
}
