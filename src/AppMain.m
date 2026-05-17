#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

// Reuse the markdown renderer from GeneratePreview.m
extern NSString *markdownToHTML(NSString *markdown);
extern NSString *getCSS(void);

// ---------------------------------------------------------------------------
// App Delegate
// ---------------------------------------------------------------------------
@interface MdairAppDelegate : NSObject <NSApplicationDelegate, WKNavigationDelegate>
@property (strong) NSMutableArray<NSWindow *> *windows;
- (IBAction)zoomIn:(id)sender;
- (IBAction)zoomOut:(id)sender;
- (IBAction)actualSize:(id)sender;
- (void)openMarkdownString:(NSString *)markdown withTitle:(NSString *)title baseDir:(NSString *)baseDir;
- (NSString *)inlineLocalImagesInHTML:(NSString *)html baseDir:(NSString *)baseDir;
- (IBAction)exportAsMdair:(id)sender;
- (IBAction)exportAsPDF:(id)sender;
- (IBAction)printDocument:(id)sender;
+ (NSPrintInfo *)a4PrintInfo;
@end

@implementation MdairAppDelegate

- (instancetype)init {
    self = [super init];
    if (self) _windows = [NSMutableArray array];
    return self;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    // If no file was opened via double-click, show a welcome window
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (self.windows.count == 0) {
            [self openMarkdownString:@"# mdair\n\nMarkdown QuickLook Previewer.\n\nDrag a `.md` or `.mdair` file onto this app or use **Open With** in Finder."
                           withTitle:@"mdair"];
        }
    });
}

- (BOOL)application:(NSApplication *)sender openFile:(NSString *)filename {
    [self openMarkdownFile:filename];
    return YES;
}

- (void)application:(NSApplication *)sender openFiles:(NSArray<NSString *> *)filenames {
    for (NSString *file in filenames) {
        [self openMarkdownFile:file];
    }
    [sender replyToOpenOrPrint:NSApplicationDelegateReplySuccess];
}

- (void)openMarkdownFile:(NSString *)path {
    if ([[path pathExtension] caseInsensitiveCompare:@"mdair"] == NSOrderedSame) {
        [self openMdairFile:path];
        return;
    }

    NSError *error = nil;
    NSString *markdown = [NSString stringWithContentsOfFile:path
                                                  encoding:NSUTF8StringEncoding
                                                     error:&error];
    if (!markdown) {
        markdown = [NSString stringWithContentsOfFile:path
                                            encoding:NSISOLatin1StringEncoding
                                               error:&error];
    }
    if (!markdown) {
        NSLog(@"Failed to read: %@", path);
        return;
    }

    NSString *title = [path lastPathComponent];
    NSString *baseDir = [path stringByDeletingLastPathComponent];
    [self openMarkdownString:markdown withTitle:title baseDir:baseDir];
    NSWindow *createdWindow = [self.windows lastObject];
    [createdWindow setRepresentedURL:[NSURL fileURLWithPath:path]];
}

- (void)openMdairFile:(NSString *)path {
    // Create temp directory
    NSString *tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:
                         [[NSUUID UUID] UUIDString]];
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:tempDir withIntermediateDirectories:YES attributes:nil error:nil];

    // Unzip using /usr/bin/unzip (host app is NOT sandboxed)
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:@"/usr/bin/unzip"];
    [task setArguments:@[@"-o", @"-q", path, @"-d", tempDir]];
    [task setStandardOutput:[NSPipe pipe]];
    [task setStandardError:[NSPipe pipe]];
    [task launch];
    [task waitUntilExit];

    if ([task terminationStatus] != 0) {
        NSLog(@"Failed to unzip .mdair file: %@", path);
        [fm removeItemAtPath:tempDir error:nil];
        return;
    }

    // Read content.md
    NSString *contentPath = [tempDir stringByAppendingPathComponent:@"content.md"];
    if (![fm fileExistsAtPath:contentPath]) {
        // Fallback: find first .md file in root
        NSArray *items = [fm contentsOfDirectoryAtPath:tempDir error:nil];
        for (NSString *item in items) {
            if ([[item pathExtension] caseInsensitiveCompare:@"md"] == NSOrderedSame) {
                contentPath = [tempDir stringByAppendingPathComponent:item];
                break;
            }
        }
    }

    NSError *error = nil;
    NSString *markdown = [NSString stringWithContentsOfFile:contentPath
                                                  encoding:NSUTF8StringEncoding
                                                     error:&error];
    if (!markdown) {
        markdown = [NSString stringWithContentsOfFile:contentPath
                                            encoding:NSISOLatin1StringEncoding
                                               error:&error];
    }
    if (!markdown) {
        NSLog(@"Failed to read content.md from .mdair: %@", path);
        [fm removeItemAtPath:tempDir error:nil];
        return;
    }

    // Render markdown to HTML, inlining assets as data URIs
    NSString *body = markdownToHTML(markdown);
    NSString *assetsDir = [tempDir stringByAppendingPathComponent:@"assets"];
    body = [self inlineAssetsFromDirectory:body assetsDir:assetsDir];

    NSString *css = getCSS();
    NSString *html = [NSString stringWithFormat:
        @"<!DOCTYPE html><html><head><meta charset='utf-8'>"
        "<style>%@</style></head><body>%@"
        "<script src='https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js'></script>"
        "<script>mermaid.initialize({startOnLoad:true,theme:'default'});</script>"
        "<script>(function(){var t=null,m=null;function s(){if(!t){t=document.createElement('div');t.id='mdair-toast';t.textContent='복사됨';document.body.appendChild(t);}t.classList.add('show');clearTimeout(m);m=setTimeout(function(){t.classList.remove('show');},1200);}document.addEventListener('copy',s);})();</script>"
        "</body></html>", css, body];

    NSString *title = [path lastPathComponent];

    NSRect frame = NSMakeRect(0, 0, 860, 700);
    NSWindowStyleMask style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                              NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;
    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                   styleMask:style
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    [window setTitle:title];
    [window center];

    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    WKWebView *webView = [[WKWebView alloc] initWithFrame:frame configuration:config];
    [webView setAllowsMagnification:YES];
    [webView setNavigationDelegate:self];
    [webView loadHTMLString:html baseURL:[NSURL fileURLWithPath:tempDir]];
    [window setContentView:webView];
    [window setRepresentedURL:[NSURL fileURLWithPath:path]];
    [window makeKeyAndOrderFront:nil];

    [self.windows addObject:window];

    // Clean up temp directory after a delay to allow WebView to load
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)),
                   dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [[NSFileManager defaultManager] removeItemAtPath:tempDir error:nil];
    });
}

- (NSString *)inlineAssetsFromDirectory:(NSString *)html assetsDir:(NSString *)assetsDir {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:assetsDir]) return html;

    NSRegularExpression *regex = [NSRegularExpression
        regularExpressionWithPattern:@"(src|srcset)=\"assets/([^\"]+)\""
        options:0 error:nil];
    if (!regex) return html;

    NSMutableString *result = [html mutableCopy];
    NSArray<NSTextCheckingResult *> *matches = [regex matchesInString:html options:0
        range:NSMakeRange(0, html.length)];

    for (NSTextCheckingResult *match in [matches reverseObjectEnumerator]) {
        NSString *attr = [html substringWithRange:[match rangeAtIndex:1]];
        NSString *filename = [html substringWithRange:[match rangeAtIndex:2]];
        NSString *filePath = [assetsDir stringByAppendingPathComponent:filename];

        if (![fm fileExistsAtPath:filePath]) continue;

        NSData *imgData = [NSData dataWithContentsOfFile:filePath];
        if (!imgData) continue;

        NSString *ext = [[filename pathExtension] lowercaseString];
        NSString *mime = @"image/png";
        if ([ext isEqualToString:@"jpg"] || [ext isEqualToString:@"jpeg"]) mime = @"image/jpeg";
        else if ([ext isEqualToString:@"gif"]) mime = @"image/gif";
        else if ([ext isEqualToString:@"svg"]) mime = @"image/svg+xml";
        else if ([ext isEqualToString:@"webp"]) mime = @"image/webp";
        else if ([ext isEqualToString:@"tiff"] || [ext isEqualToString:@"tif"]) mime = @"image/tiff";

        NSString *b64 = [imgData base64EncodedStringWithOptions:0];
        NSString *replacement = [NSString stringWithFormat:@"%@=\"data:%@;base64,%@\"", attr, mime, b64];
        [result replaceCharactersInRange:[match range] withString:replacement];
    }

    return [result copy];
}

- (void)openMarkdownString:(NSString *)markdown withTitle:(NSString *)title {
    [self openMarkdownString:markdown withTitle:title baseDir:nil];
}

- (void)openMarkdownString:(NSString *)markdown withTitle:(NSString *)title baseDir:(NSString *)baseDir {
    NSString *body = markdownToHTML(markdown);
    if (baseDir) {
        body = [self inlineLocalImagesInHTML:body baseDir:baseDir];
    }
    NSString *css = getCSS();
    NSString *html = [NSString stringWithFormat:
        @"<!DOCTYPE html><html><head><meta charset='utf-8'>"
        "<style>%@</style></head><body>%@"
        "<script src='https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js'></script>"
        "<script>mermaid.initialize({startOnLoad:true,theme:'default'});</script>"
        "<script>(function(){var t=null,m=null;function s(){if(!t){t=document.createElement('div');t.id='mdair-toast';t.textContent='복사됨';document.body.appendChild(t);}t.classList.add('show');clearTimeout(m);m=setTimeout(function(){t.classList.remove('show');},1200);}document.addEventListener('copy',s);})();</script>"
        "</body></html>", css, body];

    NSRect frame = NSMakeRect(0, 0, 860, 700);
    NSWindowStyleMask style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                              NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;
    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                   styleMask:style
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    [window setTitle:title];
    [window center];

    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    WKWebView *webView = [[WKWebView alloc] initWithFrame:frame configuration:config];
    [webView setAllowsMagnification:YES];
    [webView setNavigationDelegate:self];
    NSURL *baseURL = baseDir ? [NSURL fileURLWithPath:baseDir] : nil;
    [webView loadHTMLString:html baseURL:baseURL];
    [window setContentView:webView];
    [window makeKeyAndOrderFront:nil];

    [self.windows addObject:window];
}

- (NSString *)inlineLocalImagesInHTML:(NSString *)html baseDir:(NSString *)baseDir {
    NSRegularExpression *regex = [NSRegularExpression
        regularExpressionWithPattern:@"(src|srcset)=\"([^\"]+)\""
        options:0 error:nil];
    if (!regex) return html;

    NSMutableString *result = [html mutableCopy];
    NSArray<NSTextCheckingResult *> *matches = [regex matchesInString:html options:0
        range:NSMakeRange(0, html.length)];

    for (NSTextCheckingResult *match in [matches reverseObjectEnumerator]) {
        NSString *attr = [html substringWithRange:[match rangeAtIndex:1]];
        NSString *path = [html substringWithRange:[match rangeAtIndex:2]];

        if ([path hasPrefix:@"http://"] || [path hasPrefix:@"https://"] || [path hasPrefix:@"data:"]) continue;

        NSString *filePath;
        if ([path hasPrefix:@"/"]) {
            filePath = path;
        } else {
            filePath = [baseDir stringByAppendingPathComponent:path];
        }

        NSData *imgData = [NSData dataWithContentsOfFile:filePath];
        if (!imgData) continue;

        NSString *ext = [[path pathExtension] lowercaseString];
        NSString *mime = @"image/png";
        if ([ext isEqualToString:@"jpg"] || [ext isEqualToString:@"jpeg"]) mime = @"image/jpeg";
        else if ([ext isEqualToString:@"gif"]) mime = @"image/gif";
        else if ([ext isEqualToString:@"svg"]) mime = @"image/svg+xml";
        else if ([ext isEqualToString:@"webp"]) mime = @"image/webp";
        else if ([ext isEqualToString:@"tiff"] || [ext isEqualToString:@"tif"]) mime = @"image/tiff";

        NSString *b64 = [imgData base64EncodedStringWithOptions:0];
        NSString *replacement = [NSString stringWithFormat:@"%@=\"data:%@;base64,%@\"", attr, mime, b64];
        [result replaceCharactersInRange:[match range] withString:replacement];
    }

    return [result copy];
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    NSURL *url = navigationAction.request.URL;
    if (navigationAction.navigationType == WKNavigationTypeLinkActivated && url) {
        [[NSWorkspace sharedWorkspace] openURL:url];
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }
    decisionHandler(WKNavigationActionPolicyAllow);
}

- (WKWebView *)activeWebView {
    NSWindow *window = [NSApp keyWindow];
    if (window && [window.contentView isKindOfClass:[WKWebView class]]) {
        return (WKWebView *)window.contentView;
    }
    return nil;
}

- (IBAction)zoomIn:(id)sender {
    WKWebView *webView = [self activeWebView];
    if (webView) {
        webView.magnification = MIN(webView.magnification * 1.25, 5.0);
    }
}

- (IBAction)zoomOut:(id)sender {
    WKWebView *webView = [self activeWebView];
    if (webView) {
        webView.magnification = MAX(webView.magnification / 1.25, 0.25);
    }
}

- (IBAction)actualSize:(id)sender {
    WKWebView *webView = [self activeWebView];
    if (webView) {
        webView.magnification = 1.0;
    }
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

- (IBAction)exportAsMdair:(id)sender {
    NSWindow *window = [NSApp keyWindow];
    NSURL *src = [window representedURL];
    if (!src) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"내보낼 문서가 없습니다";
        alert.informativeText = @"먼저 .md 파일을 열어주세요.";
        [alert runModal];
        return;
    }
    NSString *srcPath = [src path];
    NSString *ext = [[srcPath pathExtension] lowercaseString];
    if ([ext isEqualToString:@"mdair"]) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"이미 .mdair 파일입니다";
        [alert runModal];
        return;
    }
    NSString *toolPath = [[NSBundle mainBundle] pathForAuxiliaryExecutable:@"mdair-convert"];
    if (!toolPath || ![[NSFileManager defaultManager] fileExistsAtPath:toolPath]) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"mdair-convert 도구를 찾을 수 없습니다";
        [alert runModal];
        return;
    }

    NSSavePanel *panel = [NSSavePanel savePanel];
    NSString *defaultName = [[[srcPath lastPathComponent] stringByDeletingPathExtension]
                             stringByAppendingPathExtension:@"mdair"];
    [panel setNameFieldStringValue:defaultName];
    [panel setAllowedFileTypes:@[@"mdair"]];
    if ([panel runModal] != NSModalResponseOK) return;
    NSString *dstPath = [[panel URL] path];

    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:toolPath];
    [task setArguments:@[srcPath, @"-o", dstPath]];
    NSPipe *errPipe = [NSPipe pipe];
    [task setStandardError:errPipe];
    [task setStandardOutput:[NSPipe pipe]];

    @try {
        [task launch];
        [task waitUntilExit];
    } @catch (NSException *exception) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"내보내기 실패";
        alert.informativeText = exception.reason ?: @"unknown";
        [alert runModal];
        return;
    }

    if ([task terminationStatus] == 0) {
        [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:dstPath]]];
    } else {
        NSData *errData = [[errPipe fileHandleForReading] readDataToEndOfFile];
        NSString *errMsg = [[NSString alloc] initWithData:errData encoding:NSUTF8StringEncoding];
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"내보내기 실패";
        alert.informativeText = errMsg.length ? errMsg : @"unknown";
        [alert runModal];
    }
}

+ (NSPrintInfo *)a4PrintInfo {
    NSPrintInfo *info = [[NSPrintInfo alloc] init];
    // A4 = 210 × 297 mm = 595.276 × 841.890 pt at 72dpi
    [info setPaperSize:NSMakeSize(595.276, 841.890)];
    [info setPaperName:@"iso-a4"];
    [info setOrientation:NSPaperOrientationPortrait];
    // ~13mm margins
    [info setLeftMargin:36.0];
    [info setRightMargin:36.0];
    [info setTopMargin:36.0];
    [info setBottomMargin:36.0];
    [info setHorizontalPagination:NSPrintingPaginationModeFit];
    [info setVerticalPagination:NSPrintingPaginationModeAutomatic];
    [info setHorizontallyCentered:NO];
    [info setVerticallyCentered:NO];
    return info;
}

- (IBAction)exportAsPDF:(id)sender {
    WKWebView *webView = [self activeWebView];
    if (!webView) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"내보낼 문서가 없습니다";
        [alert runModal];
        return;
    }

    NSWindow *window = [NSApp keyWindow];
    NSURL *src = [window representedURL];
    NSString *defaultName = @"document.pdf";
    if (src) {
        defaultName = [[[[src path] lastPathComponent] stringByDeletingPathExtension]
                       stringByAppendingPathExtension:@"pdf"];
    }

    NSSavePanel *panel = [NSSavePanel savePanel];
    [panel setNameFieldStringValue:defaultName];
    [panel setAllowedFileTypes:@[@"pdf"]];
    if ([panel runModal] != NSModalResponseOK) return;
    NSURL *dstURL = [panel URL];

    NSPrintInfo *base = [MdairAppDelegate a4PrintInfo];
    NSMutableDictionary *dict = [[base dictionary] mutableCopy];
    dict[NSPrintJobDisposition] = NSPrintSaveJob;
    dict[NSPrintJobSavingURL] = dstURL;
    NSPrintInfo *info = [[NSPrintInfo alloc] initWithDictionary:dict];
    [info setPaperSize:[base paperSize]];
    [info setOrientation:[base orientation]];
    [info setLeftMargin:[base leftMargin]];
    [info setRightMargin:[base rightMargin]];
    [info setTopMargin:[base topMargin]];
    [info setBottomMargin:[base bottomMargin]];
    [info setHorizontalPagination:[base horizontalPagination]];
    [info setVerticalPagination:[base verticalPagination]];
    [info setHorizontallyCentered:NO];
    [info setVerticallyCentered:NO];

    NSPrintOperation *op = [webView printOperationWithPrintInfo:info];
    if (!op) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"PDF 생성 실패";
        alert.informativeText = @"인쇄 작업을 생성할 수 없습니다.";
        [alert runModal];
        return;
    }
    op.showsPrintPanel = NO;
    op.showsProgressPanel = YES;
    op.jobTitle = [defaultName stringByDeletingPathExtension];

    [op runOperationModalForWindow:window
                          delegate:self
                    didRunSelector:@selector(pdfExportDidEnd:success:contextInfo:)
                       contextInfo:(__bridge_retained void *)dstURL];
}

- (void)pdfExportDidEnd:(NSPrintOperation *)op success:(BOOL)success contextInfo:(void *)contextInfo {
    NSURL *dstURL = (__bridge_transfer NSURL *)contextInfo;
    if (success && dstURL) {
        [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[dstURL]];
    } else if (!success) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"PDF 저장 실패";
        alert.informativeText = @"인쇄 작업이 실패했습니다.";
        [alert runModal];
    }
}

- (IBAction)printDocument:(id)sender {
    WKWebView *webView = [self activeWebView];
    if (!webView) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"인쇄할 문서가 없습니다";
        [alert runModal];
        return;
    }

    NSWindow *window = [NSApp keyWindow];
    NSPrintInfo *info = [MdairAppDelegate a4PrintInfo];

    NSPrintOperation *op = [webView printOperationWithPrintInfo:info];
    if (!op) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"인쇄 실패";
        alert.informativeText = @"인쇄 작업을 생성할 수 없습니다.";
        [alert runModal];
        return;
    }
    op.showsPrintPanel = YES;
    op.showsProgressPanel = YES;

    NSURL *src = [window representedURL];
    if (src) {
        op.jobTitle = [[src path] lastPathComponent];
    }

    [op runOperationModalForWindow:window
                          delegate:nil
                    didRunSelector:NULL
                       contextInfo:NULL];
}

@end

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];

        // Create menu bar
        NSMenu *menuBar = [[NSMenu alloc] init];
        NSMenuItem *appMenuItem = [[NSMenuItem alloc] init];
        [menuBar addItem:appMenuItem];
        NSMenu *appMenu = [[NSMenu alloc] init];
        [appMenu addItemWithTitle:@"About mdair" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
        [appMenu addItem:[NSMenuItem separatorItem]];
        [appMenu addItemWithTitle:@"Quit mdair" action:@selector(terminate:) keyEquivalent:@"q"];
        [appMenuItem setSubmenu:appMenu];

        NSMenuItem *fileMenuItem = [[NSMenuItem alloc] init];
        [menuBar addItem:fileMenuItem];
        NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
        [fileMenu addItemWithTitle:@"Close" action:@selector(performClose:) keyEquivalent:@"w"];
        [fileMenu addItem:[NSMenuItem separatorItem]];
        [fileMenu addItemWithTitle:@"Export as .mdair…" action:@selector(exportAsMdair:) keyEquivalent:@""];
        [fileMenu addItemWithTitle:@"Export as PDF…" action:@selector(exportAsPDF:) keyEquivalent:@""];
        [fileMenu addItem:[NSMenuItem separatorItem]];
        [fileMenu addItemWithTitle:@"Print…" action:@selector(printDocument:) keyEquivalent:@"p"];
        [fileMenuItem setSubmenu:fileMenu];

        NSMenuItem *editMenuItem = [[NSMenuItem alloc] init];
        [menuBar addItem:editMenuItem];
        NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
        [editMenu addItemWithTitle:@"Undo" action:@selector(undo:) keyEquivalent:@"z"];
        NSMenuItem *redoItem = [editMenu addItemWithTitle:@"Redo" action:@selector(redo:) keyEquivalent:@"z"];
        [redoItem setKeyEquivalentModifierMask:(NSEventModifierFlagCommand | NSEventModifierFlagShift)];
        [editMenu addItem:[NSMenuItem separatorItem]];
        [editMenu addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
        [editMenu addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
        [editMenu addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
        [editMenu addItem:[NSMenuItem separatorItem]];
        [editMenu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
        [editMenuItem setSubmenu:editMenu];

        NSMenuItem *viewMenuItem = [[NSMenuItem alloc] init];
        [menuBar addItem:viewMenuItem];
        NSMenu *viewMenu = [[NSMenu alloc] initWithTitle:@"View"];
        [viewMenu addItemWithTitle:@"Zoom In" action:@selector(zoomIn:) keyEquivalent:@"+"];
        [viewMenu addItemWithTitle:@"Zoom Out" action:@selector(zoomOut:) keyEquivalent:@"-"];
        [viewMenu addItemWithTitle:@"Actual Size" action:@selector(actualSize:) keyEquivalent:@"0"];
        [viewMenuItem setSubmenu:viewMenu];

        [app setMainMenu:menuBar];

        MdairAppDelegate *delegate = [[MdairAppDelegate alloc] init];
        [app setDelegate:delegate];
        [app activateIgnoringOtherApps:YES];
        [app run];
    }
    return 0;
}
