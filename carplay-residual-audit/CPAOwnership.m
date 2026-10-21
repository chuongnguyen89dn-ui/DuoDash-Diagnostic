// Read-only cross-reference: dpkg ownership vs on-disk injectable libraries.
// This reports a match or absence of package-file records; it never removes files.
#import <Foundation/Foundation.h>

static NSString *CPAKey(NSString *raw) {
    if (!raw.length) return @"";
    NSString *p = raw;
    if ([p hasPrefix:@"./"]) p = [@"/" stringByAppendingString:[p substringFromIndex:2]];
    if (![p hasPrefix:@"/"]) p = [@"/" stringByAppendingString:p];
    p = [p stringByStandardizingPath];
    if ([p hasPrefix:@"/var/jb/"]) p = [p substringFromIndex:7];
    return p;
}
static void CPAIndexPath(NSMutableDictionary<NSString *,NSMutableSet<NSString *> *> *index,
                         NSString *path, NSString *package) {
    if (!path.length || !package.length) return;
    NSArray *variants = @[CPAKey(path), CPAKey([path stringByResolvingSymlinksInPath])];
    for (NSString *key in variants) {
        if (!key.length) continue;
        NSMutableSet *items = index[key];
        if (!items) { items = [NSMutableSet set]; index[key] = items; }
        [items addObject:package];
    }
}
static NSSet<NSString *> *CPAInstalled(void) {
    NSString *text = [NSString stringWithContentsOfFile:@"/var/jb/var/lib/dpkg/status"
                                              encoding:NSUTF8StringEncoding error:nil];
    if (!text.length) text = [NSString stringWithContentsOfFile:@"/var/lib/dpkg/status"
                                                   encoding:NSUTF8StringEncoding error:nil];
    if (!text.length) return nil;
    NSMutableSet *set = [NSMutableSet set];
    for (NSString *para in [text componentsSeparatedByString:@"\n\n"]) {
        NSString *name = nil, *status = nil;
        for (NSString *line in [para componentsSeparatedByString:@"\n"]) {
            if ([line hasPrefix:@"Package: "]) name = [line substringFromIndex:9];
            else if ([line hasPrefix:@"Status: "]) status = [line substringFromIndex:8];
        }
        if (name.length && [status isEqualToString:@"install ok installed"]) [set addObject:name];
    }
    return set;
}
void CPAWriteOwnershipAudit(NSMutableString *out) {
    [out appendString:@"\n=== 4. DPKG / SILEO OWNERSHIP AND JB INJECTION AUDIT ===\n"];
    NSSet *installed = CPAInstalled();
    if (!installed) {
        [out appendString:@"DPKG_STATUS_UNREADABLE. Cannot prove packages removed or active.\n"];
        return;
    }
    [out appendFormat:@"DPKG_INSTALLED_COUNT %lu\n",(unsigned long)installed.count];
    NSFileManager *fm = NSFileManager.defaultManager;
    NSArray *infoDirs = @[@"/var/jb/var/lib/dpkg/info",@"/var/lib/dpkg/info"];
    NSMutableDictionary *index = [NSMutableDictionary dictionary];
    NSUInteger listCount = 0, unreadable = 0;
    BOOL readAnyDirectory = NO;
    NSMutableSet *seenMetadata = [NSMutableSet set];
    for (NSString *dir in infoDirs) {
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:dir isDirectory:&isDir] || !isDir) continue;
        readAnyDirectory = YES;
        NSArray *entries = [fm contentsOfDirectoryAtPath:dir error:nil];
        if (!entries) { [out appendFormat:@"DPKG_INFO_DIRECTORY_UNREADABLE %@\n",dir]; continue; }
        for (NSString *name in entries) {
            if (![name hasSuffix:@".list"]) continue;
            NSString *full = [dir stringByAppendingPathComponent:name];
            NSString *real = [full stringByResolvingSymlinksInPath];
            if ([seenMetadata containsObject:real]) continue;
            [seenMetadata addObject:real];
            NSString *pkg = [name substringToIndex:name.length-5];
            NSString *text = [NSString stringWithContentsOfFile:full encoding:NSUTF8StringEncoding error:nil];
            if (text == nil) { unreadable++; continue; }
            listCount++;
            for (NSString *line in [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
                if (!line.length) continue;
                CPAIndexPath(index,line,pkg);
            }
        }
    }
    [out appendFormat:@"DPKG_INFO directories=%d readable_list_files=%lu unreadable_list_files=%lu indexed_paths=%lu\n",
        readAnyDirectory,(unsigned long)listCount,(unsigned long)unreadable,(unsigned long)index.count];
    BOOL ownershipReliable = readAnyDirectory && listCount > 0 && unreadable == 0;
    if (!ownershipReliable) {
        [out appendString:@"OWNER_RESULT_INCOMPLETE: cannot classify no-owner files confidently.\n"];
    }
    NSArray *injectDirs = @[
      @"/var/jb/Library/MobileSubstrate/DynamicLibraries",
      @"/var/jb/usr/lib/TweakInject",
      @"/var/jb/Library/TweakInject"
    ];
    NSMutableSet *seenRuntimePaths = [NSMutableSet set];
    NSUInteger checked=0, owned=0, noRecord=0;
    for (NSString *dir in injectDirs) {
        for (NSString *name in [fm contentsOfDirectoryAtPath:dir error:nil] ?: @[]) {
            NSString *ext = name.pathExtension.lowercaseString;
            if (![@[@"dylib",@"plist"] containsObject:ext]) continue;
            NSString *path = [dir stringByAppendingPathComponent:name];
            NSString *real = [path stringByResolvingSymlinksInPath];
            if ([seenRuntimePaths containsObject:real]) continue;
            [seenRuntimePaths addObject:real];
            checked++;
            NSMutableSet *owners = [NSMutableSet set];
            for (NSString *key in @[CPAKey(path),CPAKey(real)]) {
                if (index[key]) [owners unionSet:index[key]];
            }
            if (owners.count) {
                owned++;
                NSArray *names = [owners.allObjects sortedArrayUsingSelector:@selector(compare:)];
                for (NSString *pkg in names) {
                    NSString *state = [installed containsObject:pkg] ? @"INSTALLED" : @"NOT_INSTALLED";
                    [out appendFormat:@"PACKAGE_OWNER %@ owner=%@ status=%@\n",name,pkg,state];
                }
            } else {
                noRecord++;
                [out appendFormat:@"%@ %@ original=%@\n",
                    ownershipReliable ? @"NO_DPKG_FILE_OWNER" : @"OWNER_UNVERIFIED",
                    name,path];
            }
        }
    }
    [out appendFormat:@"INJECTION_FILE_SUMMARY scanned=%lu owner_records=%lu no_owner_record=%lu\n",
      (unsigned long)checked,(unsigned long)owned,(unsigned long)noRecord];
    [out appendString:@"INTERPRETATION: A file with no dpkg ownership record may be manually installed, generated, or orphaned. This is not proof it is harmful or safe to delete.\n"];
    [out appendString:@"An installed package may still inject a dylib with a completely different filename. Match PACKAGE_OWNER and live DYLD_IMAGE records by filename.\n"];
    [out appendString:@"Sileo repository entries/cached download files are NOT installed packages. The source of truth for installed status here is dpkg/status.\n"];
}
