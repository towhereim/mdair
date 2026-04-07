#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

// Reuse the markdown renderer from GeneratePreview.m
extern NSString *markdownToHTML(NSString *markdown);
extern NSString *getCSS(void);

// ---------------------------------------------------------------------------
// App Delegate
// ---------------------------------------------------------------------------
@interface MdairAppDelegate : NSObject <NSApplicationDelegate>
@property (strong) NSMutableArray<NSWindow *> *windows;
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
            [self openMarkdownString:@"# mdair\n\nMarkdown QuickLook Previewer.\n\nDrag a `.md` file onto this app or use **Open With** in Finder."
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
    [self openMarkdownString:markdown withTitle:title];
}

- (void)openMarkdownString:(NSString *)markdown withTitle:(NSString *)title {
    NSString *body = markdownToHTML(markdown);
    NSString *css = getCSS();
    NSString *html = [NSString stringWithFormat:
        @"<!DOCTYPE html><html><head><meta charset='utf-8'>"
        "<style>%@</style></head><body>%@</body></html>", css, body];

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
    [webView loadHTMLString:html baseURL:nil];
    [window setContentView:webView];
    [window makeKeyAndOrderFront:nil];

    [self.windows addObject:window];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
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
        [fileMenuItem setSubmenu:fileMenu];

        [app setMainMenu:menuBar];

        MdairAppDelegate *delegate = [[MdairAppDelegate alloc] init];
        [app setDelegate:delegate];
        [app activateIgnoringOtherApps:YES];
        [app run];
    }
    return 0;
}
