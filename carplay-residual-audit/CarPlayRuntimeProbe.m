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
__attribute__((constructor))
static void CPAProbeStart(void) {
    @autoreleasepool {
        CPALogQueue = dispatch_queue_create("com.chuong.carplayaudit.log", DISPATCH_QUEUE_SERIAL);
        dispatch_async(CPALogQueue, ^{
            CPAAppendFile(@"PROBE_LOADED injection=yes version=0.1");
            CPAAppendFile([NSString stringWithFormat:@"BUNDLE_ID %@",
                  NSBundle.mainBundle.bundleIdentifier ?: @"(none)"]);
        });
        _dyld_register_func_for_add_image(CPAImageDidLoad);
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
