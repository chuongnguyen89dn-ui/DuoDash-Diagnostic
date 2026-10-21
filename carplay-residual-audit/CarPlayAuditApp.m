#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <fcntl.h>
#import <unistd.h>

extern void CPAWriteOwnershipAudit(NSMutableString *out);

static NSArray<NSString *> *CPATokens(void) {
    return @[@"duodash", @"airaw", @"airaw", @"carnav", @"carbridge", @"duoface",
             @"duonavi", @"omnicar", @"sideplay", @"geometryfix", @"carplaydsp",
             @"carplay", @"dashboard", @"gmaphud", @"carwebview", @"sensetechlab"];
}
static BOOL CPAMatches(NSString *text) {
    NSString *v = text.lowercaseString ?: @"";
    for (NSString *token in CPATokens()) if ([v containsString:token]) return YES;
    return NO;
}
static void CPAAdd(NSMutableString *out, NSString *fmt, ...) {
    va_list args; va_start(args,fmt);
    NSString *s = [[NSString alloc] initWithFormat:fmt arguments:args]; va_end(args);
    [out appendFormat:@"%@\n",s];
}
static NSString *CPARead(NSString *path) {
    return [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
}
static NSString *CPAStamp(void) {
    NSDateFormatter *d = [NSDateFormatter new];
    d.dateFormat = @"yyyy-MM-dd_HH-mm-ss"; d.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    return [d stringFromDate:[NSDate date]];
}
static NSString *CPAReportsDirectory(void) {
    return @"/var/mobile/Documents/CarPlayAudit";
}
static NSArray<NSString *> *CPAList(NSString *path) {
    return [[NSFileManager defaultManager] contentsOfDirectoryAtPath:path error:nil] ?: @[];
}
static void CPAReadPackages(NSMutableString *out) {
    CPAAdd(out,@"=== 1. INSTALLED DPKG PACKAGES ===");
    NSArray *paths = @[@"/var/jb/var/lib/dpkg/status", @"/var/lib/dpkg/status"];
    NSString *file = nil;
    for (NSString *path in paths) { file = CPARead(path); if (file.length) { CPAAdd(out,@"STATUS_PATH %@",path); break; } }
    if (!file.length) { CPAAdd(out,@"UNAVAILABLE: cannot read dpkg status. Package absence is NOT proven."); return; }
    NSUInteger count = 0, relevant = 0;
    for (NSString *block in [file componentsSeparatedByString:@"\n\n"]) {
        NSString *pkg = @"", *vers = @"", *status = @"", *desc = @"";
        for (NSString *line in [block componentsSeparatedByString:@"\n"]) {
            if ([line hasPrefix:@"Package: "]) pkg = [line substringFromIndex:9];
            if ([line hasPrefix:@"Version: "]) vers = [line substringFromIndex:9];
            if ([line hasPrefix:@"Status: "]) status = [line substringFromIndex:8];
            if ([line hasPrefix:@"Name: "]) desc = [line substringFromIndex:6];
        }
        if (![status isEqualToString:@"install ok installed"]) continue;
        count++;
        if (CPAMatches([NSString stringWithFormat:@"%@ %@",pkg,desc])) {
            relevant++;
            CPAAdd(out,@"INSTALLED %@ version=%@ name=%@",pkg,vers,desc);
        }
    }
    CPAAdd(out,@"INSTALLED_TOTAL=%lu MATCHING=%lu",(unsigned long)count,(unsigned long)relevant);
}
static void CPAReadInjectionFilters(NSMutableString *out, NSString *directory, NSString *entry) {
    if (![entry.pathExtension.lowercaseString isEqualToString:@"plist"]) return;
    NSString *path = [directory stringByAppendingPathComponent:entry];
    NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:path];
    NSDictionary *filter = [plist[@"Filter"] isKindOfClass:[NSDictionary class]] ? plist[@"Filter"] : nil;
    if (filter) CPAAdd(out,@"FILTER %@ = %@",entry,filter);
    else if (CPAMatches(entry)) CPAAdd(out,@"FILTER_UNPARSED %@ (read-only)",entry);
}
static void CPAReadFilesystem(NSMutableString *out) {
    CPAAdd(out,@"\n=== 2. FILES / RESIDUALS / INJECTION FILTERS ===");
    NSArray<NSString *> *injectionDirectories = @[
        @"/var/jb/Library/MobileSubstrate/DynamicLibraries",
        @"/Library/MobileSubstrate/DynamicLibraries",
        @"/var/jb/Library/TweakInject",
        @"/var/jb/usr/lib/TweakInject",
        @"/var/jb/usr/lib/ellekit",
        @"/var/jb/Library/LaunchDaemons",
        @"/Library/LaunchDaemons"
    ];
    NSFileManager *fm = NSFileManager.defaultManager;
    for (NSString *path in injectionDirectories) {
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:path isDirectory:&isDir] || !isDir) {
            CPAAdd(out,@"MISSING_DIRECTORY %@",path); continue;
        }
        NSArray *names = CPAList(path);
        CPAAdd(out,@"SCAN_DIRECTORY %@ entries=%lu",path,(unsigned long)names.count);
        for (NSString *name in names) {
            if ([name hasPrefix:@"."]) continue;
            // All injection modules are listed, not only named suspects.
            if (CPAMatches(name) || [name.pathExtension.lowercaseString isEqualToString:@"dylib"] ||
                [name.pathExtension.lowercaseString isEqualToString:@"plist"]) {
                CPAAdd(out,@"ON_DISK %@/%@",path,name);
            }
            CPAReadInjectionFilters(out,path,name);
        }
    }
    NSArray *residualDirs = @[
        @"/var/mobile/Library/DuoDash", @"/var/jb/Library/DuoDash",
        @"/var/jb/Library/Airaw", @"/var/mobile/Documents/DuoDash-Airaw-Logs",
        @"/var/jb/Library/Preferences", @"/var/mobile/Library/Preferences",
        @"/var/jb/Library/Application Support", @"/var/mobile/Library/Application Support"
    ];
    for (NSString *path in residualDirs) {
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:path isDirectory:&isDir] || !isDir) continue;
        NSArray *names = CPAList(path);
        CPAAdd(out,@"RESIDUAL_DIRECTORY %@ entries=%lu",path,(unsigned long)names.count);
        if (CPAMatches(path)) CPAAdd(out,@"POSSIBLE_RESIDUAL_DIRECTORY %@",path);
        for (NSString *name in names) if (CPAMatches(name))
            CPAAdd(out,@"POSSIBLE_RESIDUAL_ENTRY %@/%@",path,name);
    }
    CPAAdd(out,@"NOTE: a path on disk does not establish that it is loaded at runtime.");
}
static void CPAReadRuntime(NSMutableString *out) {
    CPAAdd(out,@"\n=== 3. LIVE CARPLAY / SPRINGBOARD DYLD PROBE ===");
    NSString *path = [CPAReportsDirectory() stringByAppendingPathComponent:@"CarPlayRuntimeProbe.log"];
    NSString *log = CPARead(path);
    if (!log.length) {
        CPAAdd(out,@"RUNTIME_PROBE_MISSING: no log yet. Respring/restart CarPlay after installation, then scan.");
        CPAAdd(out,@"Do NOT interpret this as no tweak injected.");
        return;
    }
    NSDictionary *attr = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    CPAAdd(out,@"PROBE_FILE=%@ modified=%@ size=%@",path,attr[NSFileModificationDate],attr[NSFileSize]);
    NSArray *lines = [log componentsSeparatedByString:@"\n"];
    NSUInteger start = lines.count > 1500 ? lines.count - 1500 : 0;
    for (NSUInteger i=start; i<lines.count; i++) {
        NSString *line = lines[i];
        if (line.length) CPAAdd(out,@"%@",line);
    }
    CPAAdd(out,@"NOTE: loaded images here are observed by a probe injected into the named process; old runs may persist.");
}
static void CPAReadAttribution(NSMutableString *out) {
    CPAAdd(out,@"\n=== 5. CARPLAY FRAME / SAFE AREA CALLER TRACE (OPT-IN) ===");
    NSString *p=[CPAReportsDirectory() stringByAppendingPathComponent:@"CarPlayAttributionTrace.log"];
    NSString *log=CPARead(p);
    if (!log.length) {
        CPAAdd(out,@"TRACE_MISSING. Tap ARM, respring to restart CarPlay, then mark normal/zoom. No cause established.");
        return;
    }
    NSDictionary *attrs=[[NSFileManager defaultManager] attributesOfItemAtPath:p error:nil];
    CPAAdd(out,@"TRACE_FILE %@ modified=%@ bytes=%@",p,attrs[NSFileModificationDate],attrs[NSFileSize]);
    NSArray *lines=[log componentsSeparatedByString:@"\n"];
    NSUInteger start=lines.count>1800 ? lines.count-1800 : 0;
    for (NSUInteger i=start;i<lines.count;i++) if ([lines[i] length]) CPAAdd(out,@"%@",lines[i]);
    CPAAdd(out,@"TRACE_NOTE: Caller stack/HOOK_CHAIN show code-path evidence, not conclusive blame.");
}
static void CPAReadHomeTrace(NSMutableString *out) {
    CPAAdd(out,@"\n=== 6. CARPLAY HOME / APP SWITCH TOUCH TRACE (OPT-IN) ===");
    NSString *p=[CPAReportsDirectory() stringByAppendingPathComponent:@"CarPlayHomeTouchTrace.log"];
    NSString *log=CPARead(p);
    NSString *prior=CPARead([CPAReportsDirectory() stringByAppendingPathComponent:@"CarPlayHomeTouchTrace.previous.log"]);
    if(prior.length) log=[NSString stringWithFormat:@"%@\n%@",prior,log?:@""];
    if (!log.length) {
        CPAAdd(out,@"HOME_TRACE_MISSING. Tap ARM; respring; reproduce failure; then mark HOME KET or APP KET.");
        return;
    }
    NSDictionary *attr=[NSFileManager.defaultManager attributesOfItemAtPath:p error:nil];
    CPAAdd(out,@"HOME_TRACE_FILE %@ modified=%@ bytes=%@",p,attr[NSFileModificationDate],attr[NSFileSize]);
    NSArray *lines=[log componentsSeparatedByString:@"\n"];
    NSUInteger start=lines.count>2500 ? lines.count-2500 : 0;
    for (NSUInteger i=start;i<lines.count;i++) if([lines[i] length]) CPAAdd(out,@"%@",lines[i]);
    CPAAdd(out,@"HOME_TRACE_NOTE: Last rolling 2x256KiB only; older events may be overwritten. Touch or action dispatch is not a scene-activation acknowledgement.");
    CPAAdd(out,@"HOME_TRACE_MODE: 72-hour opt-in, no forced reproduction; TRACE_STARTED must appear for active process.");
}
static NSString *CPABuildReport(void) {
    NSMutableString *out = [NSMutableString string];
    CPAAdd(out,@"CarPlay Residual Audit v0.5 - READ ONLY");
    CPAAdd(out,@"Collected %@ device=%@ iOS=%@",[NSDate date],UIDevice.currentDevice.model,UIDevice.currentDevice.systemVersion);
    CPAAdd(out,@"Purpose: determine installed package ownership, filesystem injections, and CarPlay geometry.");
    CPAAdd(out,@"Evidence levels: INSTALLED (dpkg), ON_DISK (file), PROBE (dyld image). No automatic deletion.");
    CPAReadPackages(out);
    CPAReadFilesystem(out);
    CPAReadRuntime(out);
    CPAWriteOwnershipAudit(out);
    CPAReadAttribution(out);
    CPAReadHomeTrace(out);
    CPAAdd(out,@"\n=== INTERPRETATION ===");
    CPAAdd(out,@"INSTALLED is not equal to loaded. ON_DISK is not equal to loaded.");
    CPAAdd(out,@"PROBE IMAGE records are stronger evidence of current/past injection, inspect process and timestamp.");
    CPAAdd(out,@"Absence requires readable paths plus a fresh, verified probe in the relevant CarPlay process.");
    return out;
}
@interface CPAViewController : UIViewController
@property(nonatomic,strong) UITextView *output;
@property(nonatomic,strong) UIButton *scanButton;
@property(nonatomic,strong) UIButton *shareButton;
@property(nonatomic,strong) UIButton *armButton;
@property(nonatomic,strong) UIButton *normalButton;
@property(nonatomic,strong) UIButton *zoomButton;
@property(nonatomic,strong) UIButton *stopButton;
@property(nonatomic,strong) UIButton *homeFailButton;
@property(nonatomic,strong) UIButton *appFailButton;
@property(nonatomic,strong) NSURL *reportURL;
@end
@implementation CPAViewController
- (UIButton *)makeButton:(NSString *)text selector:(SEL)selector {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.translatesAutoresizingMaskIntoConstraints = NO;
    b.backgroundColor = [UIColor colorWithRed:0.13 green:0.34 blue:0.84 alpha:1];
    b.layer.cornerRadius = 10;
    b.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [b setTitle:text forState:UIControlStateNormal];
    [b addTarget:self action:selector forControlEvents:UIControlEventTouchUpInside];
    return b;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    UILabel *titleLabel = [UILabel new];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.text = @"CarPlay Diagnostic";
    titleLabel.font = [UIFont boldSystemFontOfSize:25];
    UILabel *info = [UILabel new];
    info.translatesAutoresizingMaskIntoConstraints = NO;
    info.text = @"0.5 · Ghi Home / đổi ứng dụng tối đa 72 giờ sau khi bật, lưu log xoay vòng, không sửa DuoFace.";
    info.numberOfLines = 0;
    info.font = [UIFont systemFontOfSize:14];
    self.scanButton = [self makeButton:@"QUÉT MÁY" selector:@selector(scanTapped)];
    self.shareButton = [self makeButton:@"CHIA SẺ BÁO CÁO" selector:@selector(shareTapped)];
    self.armButton = [self makeButton:@"1. BẬT GHI LOG (72 GIỜ)" selector:@selector(armTapped)];
    self.normalButton = [self makeButton:@"2. MỐC THƯỜNG" selector:@selector(normalTapped)];
    self.zoomButton = [self makeButton:@"3. MỐC ZOOM IN" selector:@selector(zoomTapped)];
    self.stopButton = [self makeButton:@"4. DỪNG TRUY VẾT" selector:@selector(stopTapped)];
    self.homeFailButton = [self makeButton:@"HOME KẸT" selector:@selector(homeFailTapped)];
    self.appFailButton = [self makeButton:@"APP KẸT" selector:@selector(appFailTapped)];
    for (UIButton *b in @[self.armButton,self.normalButton,self.zoomButton,self.stopButton])
        b.titleLabel.font=[UIFont boldSystemFontOfSize:13];
    self.stopButton.backgroundColor = UIColor.systemGrayColor;
    self.homeFailButton.titleLabel.font=[UIFont boldSystemFontOfSize:13];
    self.appFailButton.titleLabel.font=[UIFont boldSystemFontOfSize:13];
    self.homeFailButton.backgroundColor=UIColor.systemOrangeColor;
    self.appFailButton.backgroundColor=UIColor.systemOrangeColor;
    self.shareButton.enabled = NO;
    self.shareButton.alpha = 0.5;
    self.output = [UITextView new];
    self.output.translatesAutoresizingMaskIntoConstraints = NO;
    self.output.editable = NO;
    self.output.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    self.output.backgroundColor = UIColor.secondarySystemBackgroundColor;
    self.output.layer.cornerRadius = 10;
    self.output.text = @"Bật ghi log, respring một lần và dùng CarPlay bình thường. KHÔNG cần thử liên tục. Khi lỗi bất chợt xảy ra, nhấn HOME KẸT hoặc APP KẸT trên iPhone, rồi DỪNG / QUÉT MÁY / CHIA SẺ.\n\nTheo dõi cảm ứng tối đa 72 giờ, lưu 2 file khoảng 256KB mỗi file. Truy vết frame cũ chỉ chạy 5 phút. Không chỉnh DuoFace.";
    for (UIView *v in @[titleLabel,info,self.armButton,self.normalButton,self.zoomButton,self.stopButton,self.homeFailButton,self.appFailButton,self.scanButton,self.shareButton,self.output])
        [self.view addSubview:v];
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.topAnchor constraintEqualToAnchor:safe.topAnchor constant:14],
        [titleLabel.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16],
        [titleLabel.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16],
        [info.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:8],
        [info.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [info.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],
        [self.armButton.topAnchor constraintEqualToAnchor:info.bottomAnchor constant:10],
        [self.armButton.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [self.armButton.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],
        [self.armButton.heightAnchor constraintEqualToConstant:38],
        [self.normalButton.topAnchor constraintEqualToAnchor:self.armButton.bottomAnchor constant:7],
        [self.normalButton.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [self.normalButton.heightAnchor constraintEqualToConstant:38],
        [self.zoomButton.topAnchor constraintEqualToAnchor:self.normalButton.topAnchor],
        [self.zoomButton.leadingAnchor constraintEqualToAnchor:self.normalButton.trailingAnchor constant:7],
        [self.zoomButton.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],
        [self.zoomButton.widthAnchor constraintEqualToAnchor:self.normalButton.widthAnchor],
        [self.zoomButton.heightAnchor constraintEqualToConstant:38],
        [self.stopButton.topAnchor constraintEqualToAnchor:self.normalButton.bottomAnchor constant:7],
        [self.stopButton.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [self.stopButton.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],
        [self.stopButton.heightAnchor constraintEqualToConstant:38],
        [self.homeFailButton.topAnchor constraintEqualToAnchor:self.stopButton.bottomAnchor constant:7],
        [self.homeFailButton.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [self.homeFailButton.heightAnchor constraintEqualToConstant:38],
        [self.appFailButton.topAnchor constraintEqualToAnchor:self.homeFailButton.topAnchor],
        [self.appFailButton.leadingAnchor constraintEqualToAnchor:self.homeFailButton.trailingAnchor constant:7],
        [self.appFailButton.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],
        [self.appFailButton.widthAnchor constraintEqualToAnchor:self.homeFailButton.widthAnchor],
        [self.appFailButton.heightAnchor constraintEqualToConstant:38],
        [self.scanButton.topAnchor constraintEqualToAnchor:self.homeFailButton.bottomAnchor constant:9],
        [self.scanButton.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [self.scanButton.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],
        [self.scanButton.heightAnchor constraintEqualToConstant:42],
        [self.shareButton.topAnchor constraintEqualToAnchor:self.scanButton.bottomAnchor constant:8],
        [self.shareButton.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [self.shareButton.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],
        [self.shareButton.heightAnchor constraintEqualToConstant:42],
        [self.output.topAnchor constraintEqualToAnchor:self.shareButton.bottomAnchor constant:12],
        [self.output.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [self.output.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],
        [self.output.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-10]
    ]];
}
- (void)logMarker:(NSString *)mark {
    NSString *dir=CPAReportsDirectory();
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *p=[dir stringByAppendingPathComponent:@"CarPlayAttributionTrace.log"];
    int fd=open(p.fileSystemRepresentation,O_WRONLY|O_CREAT|O_APPEND,0644);
    if (fd<0) { self.output.text=@"Không ghi được dấu mốc: kiểm tra quyền truy cập."; return; }
    NSString *line=[NSString stringWithFormat:@"%.3f pid=%d USER_MARK %@\n",
                    NSDate.date.timeIntervalSince1970,getpid(),mark];
    NSData *d=[line dataUsingEncoding:NSUTF8StringEncoding];
    write(fd,d.bytes,d.length); close(fd);
    self.output.text=[NSString stringWithFormat:@"%@\n\n%@",mark,self.output.text?:@""];
}
- (void)armTapped {
    NSString *dir=CPAReportsDirectory();
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *p=[dir stringByAppendingPathComponent:@"AttributionEnabled"];
    NSError *err=nil;
    BOOL ok=[@"enabled" writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:&err];
    if (!ok) { self.output.text=[NSString stringWithFormat:@"Bật truy vết thất bại: %@",err]; return; }
    [self logMarker:@"ARMED_REQUEST; RESPRING_NOW to start new CarPlay process"];
    self.output.text=@"Đã bật ghi log. Respring một lần, sử dụng CarPlay bình thường trong tối đa 72 giờ. Khi lỗi xảy ra, đánh dấu HOME KẸT hoặc APP KẸT; xuất báo cáo ngay sau đó.";
}
- (void)normalTapped {
    [self logMarker:@"PHASE_NORMAL"];
}
- (void)zoomTapped {
    [self logMarker:@"PHASE_ZOOM_IN"];
}
- (void)markHomeProblem:(NSString *)name {
    [self logMarker:name];
    NSString *p=[CPAReportsDirectory() stringByAppendingPathComponent:@"CarPlayHomeTouchTrace.log"];
    int fd=open(p.fileSystemRepresentation,O_WRONLY|O_CREAT|O_APPEND,0644);
    if(fd<0)return;
    NSString *line=[NSString stringWithFormat:@"%.3f pid=%d USER_MARK %@\n",
                     NSDate.date.timeIntervalSince1970,getpid(),name];
    NSData *d=[line dataUsingEncoding:NSUTF8StringEncoding];
    write(fd,d.bytes,d.length);close(fd);
}
- (void)homeFailTapped { [self markHomeProblem:@"HOME_UNRESPONSIVE"]; }
- (void)appFailTapped { [self markHomeProblem:@"APP_SWITCH_UNRESPONSIVE"]; }
- (void)stopTapped {
    NSString *p=[CPAReportsDirectory() stringByAppendingPathComponent:@"AttributionEnabled"];
    [[NSFileManager defaultManager] removeItemAtPath:p error:nil];
    [self logMarker:@"TRACE_STOP_REQUEST; captured log retained"];
}
- (void)scanTapped {
    NSString *report = CPABuildReport();
    NSString *dir = CPAReportsDirectory();
    NSError *error = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:&error];
    NSString *path = [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"CarPlayAudit-%@.txt",CPAStamp()]];
    BOOL ok = !error && [report writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error];
    self.output.text = report;
    [self.output scrollRangeToVisible:NSMakeRange(0,0)];
    self.reportURL = ok ? [NSURL fileURLWithPath:path] : nil;
    self.shareButton.enabled = ok; self.shareButton.alpha = ok ? 1 : 0.5;
    if (!ok) self.output.text = [NSString stringWithFormat:@"Lỗi lưu file: %@\n\n%@",error,report];
}
- (void)shareTapped {
    if (!self.reportURL) return;
    UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[self.reportURL] applicationActivities:nil];
    share.popoverPresentationController.sourceView = self.shareButton;
    share.popoverPresentationController.sourceRect = self.shareButton.bounds;
    [self presentViewController:share animated:YES completion:nil];
}
@end
@interface CPADelegate : UIResponder<UIApplicationDelegate>
@property(nonatomic,strong) UIWindow *window;
@end
@implementation CPADelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    (void)application; (void)options;
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [CPAViewController new];
    [self.window makeKeyAndVisible];
    return YES;
}
@end
int main(int argc, char **argv) {
    @autoreleasepool { return UIApplicationMain(argc,argv,nil,NSStringFromClass([CPADelegate class])); }
}
