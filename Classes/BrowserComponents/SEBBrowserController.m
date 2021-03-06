//
//  SEBBrowserController.m
//  SafeExamBrowser
//
//  Created by Daniel R. Schneider on 06/10/14.
//  Copyright (c) 2010-2015 Daniel R. Schneider, ETH Zurich,
//  Educational Development and Technology (LET),
//  based on the original idea of Safe Exam Browser
//  by Stefan Schneider, University of Giessen
//  Project concept: Thomas Piendl, Daniel R. Schneider,
//  Dirk Bauer, Kai Reuter, Tobias Halbherr, Karsten Burger, Marco Lehre,
//  Brigitte Schmucki, Oliver Rahs. French localization: Nicolas Dunand
//
//  ``The contents of this file are subject to the Mozilla Public License
//  Version 1.1 (the "License"); you may not use this file except in
//  compliance with the License. You may obtain a copy of the License at
//  http://www.mozilla.org/MPL/
//
//  Software distributed under the License is distributed on an "AS IS"
//  basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See the
//  License for the specific language governing rights and limitations
//  under the License.
//
//  The Original Code is Safe Exam Browser for Mac OS X.
//
//  The Initial Developer of the Original Code is Daniel R. Schneider.
//  Portions created by Daniel R. Schneider are Copyright
//  (c) 2010-2015 Daniel R. Schneider, ETH Zurich, Educational Development
//  and Technology (LET), based on the original idea of Safe Exam Browser
//  by Stefan Schneider, University of Giessen. All Rights Reserved.
//
//  Contributor(s): ______________________________________.
//

#import "SEBBrowserController.h"
#import "SEBBrowserWindowDocument.h"
#import "SEBBrowserOpenWindowWebView.h"
#import "NSWindow+SEBWindow.h"
#import "WebKit+WebKitExtensions.h"
#import "SEBConfigFileManager.h"

#include "WebStorageManagerPrivate.h"
#include "WebPreferencesPrivate.h"

@implementation SEBBrowserController


- (instancetype)init
{
    self = [super init];
    if (self) {
        
        self.openBrowserWindowsWebViews = [NSMutableArray new];
        
        // Initialize SEB dock item menu for open browser windows/WebViews
        SEBDockItemMenu *dockMenu = [[SEBDockItemMenu alloc] initWithTitle:@""];
        self.openBrowserWindowsWebViewsMenu = dockMenu;
        
    }
    return self;
}


// Create custom WebPreferences with bugfix for local storage not persisting application quit/start
- (void) setCustomWebPreferencesForWebView:(SEBWebView *)webView
{
    // Set browser user agent according to settings
    NSUserDefaults *preferences = [NSUserDefaults standardUserDefaults];
    NSString* versionString = [[MyGlobals sharedMyGlobals] infoValueForKey:@"CFBundleShortVersionString"];
    NSString *overrideUserAgent;
    
    if ([preferences secureIntegerForKey:@"org_safeexambrowser_SEB_browserUserAgentMac"] == browserUserAgentModeMacDefault) {
        overrideUserAgent = [[MyGlobals sharedMyGlobals] valueForKey:@"defaultUserAgent"];
    } else {
        overrideUserAgent = [preferences secureStringForKey:@"org_safeexambrowser_SEB_browserUserAgentMacCustom"];
    }
    // Add "SEB <version number>" to the browser's user agent, so the LMS SEB plugins recognize us
    overrideUserAgent = [overrideUserAgent stringByAppendingString:[NSString stringWithFormat:@" SEB/%@", versionString]];
    [webView setCustomUserAgent:overrideUserAgent];
    
    DDLogDebug(@"Testing if WebStorageManager respondsToSelector:@selector(_storageDirectoryPath)");
    if ([WebStorageManager respondsToSelector: @selector(_storageDirectoryPath)]) {
        NSString* dbPath = [WebStorageManager _storageDirectoryPath];
        WebPreferences* prefs = [webView preferences];
        if (![prefs respondsToSelector:@selector(_localStorageDatabasePath)]) {
            DDLogError(@"WebPreferences did not respond to selector _localStorageDatabasePath. Local Storage won't be available!");
            return;
        }
        NSString* localDBPath = [prefs _localStorageDatabasePath];
        [prefs setAutosaves:YES];  //SET PREFS AUTOSAVE FIRST otherwise settings aren't saved.
        [prefs setWebGLEnabled:YES];
        
        if ([preferences secureBoolForKey:@"org_safeexambrowser_SEB_removeLocalStorage"]) {
            [prefs setLocalStorageEnabled:NO];
            
            [webView setPreferences:prefs];
        } else {
            // Check if paths match and if not, create a new local storage database file
            // (otherwise localstorage file is erased when starting program)
            // Thanks to Derek Wade!
            if ([localDBPath isEqualToString:dbPath] == NO) {
                // Define application cache quota
                static const unsigned long long defaultTotalQuota = 10 * 1024 * 1024; // 10MB
                static const unsigned long long defaultOriginQuota = 5 * 1024 * 1024; // 5MB
                [prefs setApplicationCacheTotalQuota:defaultTotalQuota];
                [prefs setApplicationCacheDefaultOriginQuota:defaultOriginQuota];
                
                [prefs setOfflineWebApplicationCacheEnabled:YES];
                
                [prefs setDatabasesEnabled:YES];
                //        [prefs setDeveloperExtrasEnabled:[[NSUserDefaults standardUserDefaults] boolForKey: @"developer"]];
#ifdef DEBUG
                [prefs setDeveloperExtrasEnabled:YES];
#endif
                [prefs _setLocalStorageDatabasePath:dbPath];
                [prefs setLocalStorageEnabled:YES];
                
                [webView setPreferences:prefs];
            } else {
                [prefs setLocalStorageEnabled:YES];
            }
        }
    } else {
        DDLogError(@"WebStorageManager did not respond to selector _storageDirectoryPath. Local Storage won't be available!");
    }
}


// Open a new web browser window document
- (SEBBrowserWindowDocument *) openBrowserWindowDocument
{
    SEBBrowserWindowDocument *browserWindowDocument = [[NSDocumentController sharedDocumentController] openUntitledDocumentOfType:@"DocumentType" display:YES];
    
    // Set the reference to the browser controller in the browser window controller instance
    browserWindowDocument.mainWindowController.browserController = self;
    
    // Set the reference to the browser controller in the browser window instance
    SEBBrowserWindow *newWindow = (SEBBrowserWindow *)browserWindowDocument.mainWindowController.window;
    newWindow.browserController = self;
    
    return browserWindowDocument;
}


// Open a new WebView and show its window
- (SEBWebView *) openAndShowWebView
{
    SEBBrowserWindowDocument *browserWindowDocument = [self openBrowserWindowDocument];

    SEBBrowserWindow *newWindow = (SEBBrowserWindow *)browserWindowDocument.mainWindowController.window;
    SEBWebView *newWindowWebView = browserWindowDocument.mainWindowController.webView;
    newWindowWebView.creatingWebView = nil;

    // Create custom WebPreferences with bugfix for local storage not persisting application quit/start
    [self setCustomWebPreferencesForWebView:newWindowWebView];

    [self addBrowserWindow:(SEBBrowserWindow *)browserWindowDocument.mainWindowController.window
               withWebView:newWindowWebView
                 withTitle:NSLocalizedString(@"Untitled", @"Title of a new opened browser window; Untitled")];
    
    [browserWindowDocument.mainWindowController.window setSharingType: NSWindowSharingNone];  //don't allow other processes to read window contents
    NSUserDefaults *preferences = [NSUserDefaults standardUserDefaults];
    BOOL elevateWindowLevels = [preferences secureBoolForKey:@"org_safeexambrowser_elevateWindowLevels"];
    // Order new browser window to the front of our level
    [self setLevelForBrowserWindow:browserWindowDocument.mainWindowController.window elevateLevels:elevateWindowLevels];
    self.activeBrowserWindow = newWindow;
    [browserWindowDocument.mainWindowController showWindow:self];
    [newWindow makeKeyAndOrderFront:self];
    
    return newWindowWebView;
}


- (void) closeWebView:(SEBWebView *) webViewToClose
{
    // Remove the entry for the WebView in a browser window from the array and dock item menu of open browser windows/WebViews
    [self removeBrowserWindow:(SEBBrowserWindow *)webViewToClose.window withWebView:webViewToClose];
    
    // Get the document for the web view
    id myDocument = [[NSDocumentController sharedDocumentController] documentForWindow:webViewToClose.window];

    // Close document and therefore also window
    DDLogInfo(@"Now closing new document browser window. %@", webViewToClose);

    [myDocument close];
}


// Show new window containing webView
- (void) webViewShow:(SEBWebView *)sender
{
    SEBBrowserWindowDocument *browserWindowDocument = [[NSDocumentController sharedDocumentController] documentForWindow:[sender window]];
//    [[sender window] setSharingType: NSWindowSharingNone];  //don't allow other processes to read window contents
//    BOOL elevateWindowLevels = [[NSUserDefaults standardUserDefaults] secureBoolForKey:@"org_safeexambrowser_elevateWindowLevels"];
//    [self setLevelForBrowserWindow:[sender window] elevateLevels:elevateWindowLevels];

    [browserWindowDocument showWindows];
    DDLogInfo(@"Now showing new document browser window for: %@",sender);
    // Order new browser window to the front
    //[[sender window] makeKeyAndOrderFront:self];
}


// Set up SEB Browser and open the main window
- (void) openMainBrowserWindow {
    
    // Save current WebKit Cookie Policy
     NSHTTPCookieAcceptPolicy cookiePolicy = [[NSHTTPCookieStorage sharedHTTPCookieStorage] cookieAcceptPolicy];
     if (cookiePolicy == NSHTTPCookieAcceptPolicyAlways) DDLogInfo(@"NSHTTPCookieAcceptPolicyAlways");
     if (cookiePolicy == NSHTTPCookieAcceptPolicyOnlyFromMainDocumentDomain) DDLogInfo(@"NSHTTPCookieAcceptPolicyOnlyFromMainDocumentDomain");
    
    NSUserDefaults *preferences = [NSUserDefaults standardUserDefaults];
    
    // Preconfigure Window for full screen
    BOOL mainBrowserWindowShouldBeFullScreen = ([preferences secureIntegerForKey:@"org_safeexambrowser_SEB_browserViewMode"] == browserViewModeFullscreen);
    
    DDLogInfo(@"Open MainBrowserWindow with browserViewMode: %hhd", mainBrowserWindowShouldBeFullScreen);
    
    // Open and maximize the browser window
    // (this is done here, after presentation options are set,
    // because otherwise menu bar and dock are deducted from screen size)
    SEBBrowserWindowDocument *browserWindowDocument = [self openBrowserWindowDocument];
    
    self.webView = browserWindowDocument.mainWindowController.webView;
    self.webView.creatingWebView = nil;
    
    // Load start URL from the system's user defaults
    NSString *urlText = [preferences secureStringForKey:@"org_safeexambrowser_SEB_startURL"];
    // Save the default user agent of the installed WebKit version
    NSString *customUserAgent = [self.webView userAgentForURL:[NSURL URLWithString:urlText]];
    [[MyGlobals sharedMyGlobals] setValue:customUserAgent forKey:@"defaultUserAgent"];

    // Create custom WebPreferences with bugfix for local storage not persisting application quit/start
    [self setCustomWebPreferencesForWebView:self.webView];
    
    self.mainBrowserWindow = (SEBBrowserWindow *)browserWindowDocument.mainWindowController.window;

    // Check if the active screen (where the window is opened) changed in between opening dock
    if (self.mainBrowserWindow.screen != self.dockController.window.screen) {
        // Post a notification that the main screen changed
        [[NSNotificationCenter defaultCenter]
         postNotificationName:@"mainScreenChanged" object:self];
    }

    // Set the flag indicating if the main browser window should be displayed full screen
    self.mainBrowserWindow.isFullScreen = mainBrowserWindowShouldBeFullScreen;
    
    if (mainBrowserWindowShouldBeFullScreen) {
        [self.mainBrowserWindow setToolbar:nil];
        [self.mainBrowserWindow setStyleMask:NSBorderlessWindowMask];
        [self.mainBrowserWindow setReleasedWhenClosed:YES];
    }
    
    [self.mainBrowserWindow setSharingType: NSWindowSharingNone];  //don't allow other processes to read window contents
    [self.mainBrowserWindow setCalculatedFrame];
    if ([[NSUserDefaults standardUserDefaults] secureBoolForKey:@"org_safeexambrowser_elevateWindowLevels"]) {
        [self.mainBrowserWindow newSetLevel:NSMainMenuWindowLevel+3];
    }
    [[NSRunningApplication currentApplication] activateWithOptions:(NSApplicationActivateAllWindows | NSApplicationActivateIgnoringOtherApps)];
    
    // Setup bindings to the preferences window close button
    NSButton *closeButton = [self.mainBrowserWindow standardWindowButton:NSWindowCloseButton];
    
    [closeButton bind:@"enabled"
             toObject:[SEBEncryptedUserDefaultsController sharedSEBEncryptedUserDefaultsController]
          withKeyPath:@"values.org_safeexambrowser_SEB_allowQuit"
              options:nil];
    
    [self addBrowserWindow:self.mainBrowserWindow withWebView:self.webView withTitle:NSLocalizedString(@"Main Browser Window", nil)];
    
    //[self.browserWindow setCollectionBehavior:NSWindowCollectionBehaviorFullScreenPrimary];
    [self.mainBrowserWindow makeMainWindow];
    [self.mainBrowserWindow makeKeyAndOrderFront:self];
    self.activeBrowserWindow = self.mainBrowserWindow;
    
    DDLogInfo(@"Open MainBrowserWindow with start URL: %@", urlText);
    
    [self openURLString:urlText withSEBUserAgentInWebView:self.webView];
}


- (void) openURLString:(NSString *)urlText withSEBUserAgentInWebView:(SEBWebView *)webView
{
    // Load start URL into browser window
    [[webView mainFrame] loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:urlText]]];
}


// Adjust the size of the main browser window and bring it forward
- (void) adjustMainBrowserWindow
{
    if (self.mainBrowserWindow.isVisible) {
        [self.mainBrowserWindow setCalculatedFrame];
        [self.mainBrowserWindow makeKeyAndOrderFront:self];
    }
}


// Change window level of all open browser windows
- (void) allBrowserWindowsChangeLevel:(BOOL)allowApps
{
    NSArray *openWindowDocuments = [[NSDocumentController sharedDocumentController] documents];
    SEBBrowserWindowDocument *openWindowDocument;
    for (openWindowDocument in openWindowDocuments) {
        NSWindow *browserWindow = openWindowDocument.mainWindowController.window;
        [self setLevelForBrowserWindow:browserWindow elevateLevels:!allowApps];
    }
    // If the main browser window is displayed fullscreen and switching to apps is allowed,
    // we make the window stationary, so that it isn't scaled down from Exposé
    if ([[NSUserDefaults standardUserDefaults] secureBoolForKey:@"org_safeexambrowser_SEB_allowSwitchToApplications"] && self.mainBrowserWindow.isFullScreen) {
        self.mainBrowserWindow.collectionBehavior = NSWindowCollectionBehaviorStationary;
    }

    [[NSRunningApplication currentApplication] activateWithOptions:(NSApplicationActivateAllWindows | NSApplicationActivateIgnoringOtherApps)];
    [self.mainBrowserWindow makeKeyAndOrderFront:self];
}


- (void) setLevelForBrowserWindow:(NSWindow *)browserWindow elevateLevels:(BOOL)elevateLevels
{
    if (elevateLevels) {
        if (self.mainBrowserWindow.isFullScreen && browserWindow != self.mainBrowserWindow) {
            // If the main browser window is displayed fullscreen, then all auxillary windows
            // get a higher level, to float on top
            [browserWindow newSetLevel:NSMainMenuWindowLevel+4];
        } else {
            [browserWindow newSetLevel:NSMainMenuWindowLevel+3];
        }
    } else {
        
        // Order new browser window to the front of our level
        if (self.mainBrowserWindow.isFullScreen && browserWindow != self.mainBrowserWindow) {
            // If the main browser window is displayed fullscreen, then all auxillary windows
            // get a higher level, to float on top
            [browserWindow newSetLevel:NSNormalWindowLevel+1];
        } else {
            [browserWindow newSetLevel:NSNormalWindowLevel];
        }
        //[browserWindow orderFront:self];
    }
}


// Open an allowed additional resource in a new browser window
- (void)openResourceWithURL:(NSString *)URL andTitle:(NSString *)title
{
    SEBBrowserWindowDocument *browserWindowDocument = [[NSDocumentController sharedDocumentController] openUntitledDocumentOfType:@"DocumentType" display:YES];
    NSWindow *additionalBrowserWindow = browserWindowDocument.mainWindowController.window;
    [additionalBrowserWindow setSharingType: NSWindowSharingNone];  //don't allow other processes to read window contents
    [(SEBBrowserWindow *)additionalBrowserWindow setCalculatedFrame];
    BOOL elevateWindowLevels = [[NSUserDefaults standardUserDefaults] secureBoolForKey:@"org_safeexambrowser_elevateWindowLevels"];
    [self setLevelForBrowserWindow:additionalBrowserWindow elevateLevels:elevateWindowLevels];

    [[NSRunningApplication currentApplication] activateWithOptions:(NSApplicationActivateAllWindows | NSApplicationActivateIgnoringOtherApps)];
    
    //[additionalBrowserWindow makeKeyAndOrderFront:self];
    
    DDLogInfo(@"Open additional browser window with URL: %@", URL);
    
    // Load start URL into browser window
    [[browserWindowDocument.mainWindowController.webView mainFrame] loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:URL]]];
}


- (void) downloadAndOpenSebConfigFromURL:(NSURL *)url
{
    NSUserDefaults *preferences = [NSUserDefaults standardUserDefaults];
    if ([preferences secureBoolForKey:@"org_safeexambrowser_SEB_downloadAndOpenSebConfig"]) {
        // Check if SEB is in exam mode = private UserDefauls are switched on
        if (NSUserDefaults.userDefaultsPrivate) {
            // If yes, we don't download the .seb file
            NSRunAlertPanel(NSLocalizedString(@"Loading New SEB Settings Not Allowed!", nil),
                            NSLocalizedString(@"SEB is already running in exam mode and it is not allowed to interupt this by starting another exam. Finish the exam and quit SEB before starting another exam.", nil),
                            NSLocalizedString(@"OK", nil), nil, nil);
        } else {
            NSError *error = nil;
            // SEB isn't in exam mode: reconfiguring it is allowed
            NSData *sebFileData = [self downloadSebConfigFromURL:url error:&error];
            
            if(error) {
                 [self.mainBrowserWindow presentError:error modalForWindow:self.mainBrowserWindow delegate:nil didPresentSelector:NULL contextInfo:NULL];
            }
            
            BOOL isFromFile = [url.scheme length] == 0 || [url.scheme isEqualToString:@"file"];
            SEBConfigFileManager *configFileManager = [[SEBConfigFileManager alloc] init];
            
            // Get current config path
            NSURL *currentConfigPath = [[MyGlobals sharedMyGlobals] currentConfigURL];
            if(isFromFile)
            {
                // Store the URL of the .seb file as current config file path
                [[MyGlobals sharedMyGlobals] setCurrentConfigURL:[NSURL URLWithString:url.lastPathComponent]]; // absoluteString]];
            }
            
            if ([configFileManager storeDecryptedSEBSettings:sebFileData forEditing:NO]) {
                
                // Post a notification that it was requested to restart SEB with changed settings
                [[NSNotificationCenter defaultCenter]
                 postNotificationName:@"requestRestartNotification" object:self];
                
            } else {
                if(isFromFile)
                {
                    // if decrypting new settings wasn't successfull, we have to restore the path to the old settings
                    [[MyGlobals sharedMyGlobals] setCurrentConfigURL:currentConfigPath];
                }
            }
        }
    }
}

- (NSData *) downloadSebConfigFromURL:(NSURL *)url error:(NSError **)error
{
    NSData *sebFileData = nil;
    // Download the .seb file directly into memory (not onto disc like other files)
    if ([url.scheme isEqualToString:@"seb"]) {
        // If it's a seb:// URL, we try to download it by http
        NSURL *httpURL = [[NSURL alloc] initWithScheme:@"http" host:url.host path:url.path];
        sebFileData = [NSData dataWithContentsOfURL:httpURL options:NSDataReadingUncached error:error];
    }
    else if([url.scheme isEqualToString:@"sebs"]) {
        // If that didn't work, we try to download it by https
        NSURL *httpsURL = [[NSURL alloc] initWithScheme:@"https" host:url.host path:url.path];
        sebFileData = [NSData dataWithContentsOfURL:httpsURL options:NSDataReadingUncached error:error];
        // Still couldn't download the .seb file: present an error and abort
    }
    else {
        sebFileData = [NSData dataWithContentsOfURL:url options:NSDataReadingUncached error:error];
    }
    if (*error) {
#ifdef DEBUG
        DDLogVerbose(@"Open config %@, error: %@", [url absoluteString], [*error description]);
#else
        DDLogError(@"Open config %@, error: %@", [url absoluteString], [*error description]);
#endif
    }
    return sebFileData;
}

// Set web page title for a window/WebView
- (void) setTitle:(NSString *)title forWindow:(SEBBrowserWindow *)browserWindow withWebView:(SEBWebView *)webView
{
    for (SEBBrowserOpenWindowWebView *openWindowWebView in self.openBrowserWindowsWebViews) {
        if ([openWindowWebView.webView isEqualTo:webView]) {
            [openWindowWebView setTitle: title];
            [self.openBrowserWindowsWebViewsMenu setPopoverMenuSize];
        }
    }
    [self setStateForWindow:browserWindow withWebView:webView];
}


- (void) setStateForWindow:(SEBBrowserWindow *)browserWindow withWebView:(SEBWebView *)webView
{
    DDLogDebug(@"setStateForWindow: %@ withWebView: %@", browserWindow, webView);

    for (SEBBrowserOpenWindowWebView *openWindowWebView in self.openBrowserWindowsWebViews) {
        if ([openWindowWebView.webView isEqualTo:webView]) {
            [openWindowWebView setState:NSOnState];
            DDLogDebug(@"setState: NSOnState: %@", webView);
        } else {
            [openWindowWebView setState:NSOffState];
        }
    }
}


// Add an entry for a WebView in a browser window into the array and dock item menu of open browser windows/WebViews
- (void) addBrowserWindow:(SEBBrowserWindow *)newBrowserWindow withWebView:(SEBWebView *)newWebView withTitle:(NSString *)newTitle
{
    SEBBrowserOpenWindowWebView *newWindowWebView = [[SEBBrowserOpenWindowWebView alloc] initWithTitle:newTitle action:@selector(openWindowSelected:) keyEquivalent:@""];
    newWindowWebView.browserWindow = newBrowserWindow;
    newWindowWebView.webView = newWebView;
    newWindowWebView.title = newTitle;
    NSImage *browserWindowImage;
    [newWindowWebView setTarget:self];

    [self.openBrowserWindowsWebViews addObject:newWindowWebView];
    
    int numberOfItems = self.openBrowserWindowsWebViews.count;

    if (numberOfItems == 1) {
        browserWindowImage = [NSImage imageNamed:@"ExamIcon"];
    } else {
        browserWindowImage = [NSImage imageNamed:@"BrowserIcon"];
    }
    [browserWindowImage setSize:NSMakeSize(16, 16)];
    [newWindowWebView setImage:browserWindowImage];

    if (numberOfItems == 2) {
        [self.openBrowserWindowsWebViewsMenu insertItem:[NSMenuItem separatorItem] atIndex:1];
    }
    
    [self.openBrowserWindowsWebViewsMenu insertItem:newWindowWebView atIndex:1];
}


// Remove an entry for a WebView in a browser window from the array and dock item menu of open browser windows/WebViews
- (void) removeBrowserWindow:(SEBBrowserWindow *)browserWindow withWebView:(SEBWebView *)webView
{
    SEBBrowserOpenWindowWebView *itemToRemove;
    for (SEBBrowserOpenWindowWebView *openWindowWebView in self.openBrowserWindowsWebViews) {
        if ([openWindowWebView.webView isEqualTo:webView]) {
            itemToRemove = openWindowWebView;
            break;
        }
    }
    [self.openBrowserWindowsWebViews removeObject:itemToRemove];
    [self.openBrowserWindowsWebViewsMenu removeItem:itemToRemove];
    if (self.openBrowserWindowsWebViews.count == 1) {
        [self.openBrowserWindowsWebViewsMenu removeItemAtIndex:1];
    }
}


- (void) openWindowSelected:(SEBBrowserOpenWindowWebView *)sender
{
    DDLogInfo(@"Selected menu item: %@", sender);

    [[NSRunningApplication currentApplication] activateWithOptions:(NSApplicationActivateAllWindows | NSApplicationActivateIgnoringOtherApps)];
    [sender.browserWindow makeKeyAndOrderFront:self];
}


// Close all additional browser windows (except the main browser window)
- (void) closeAllAdditionalBrowserWindows
{
    NSArray *openWindowDocuments = [[NSDocumentController sharedDocumentController] documents];
    SEBBrowserWindowDocument *openWindowDocument;
    for (openWindowDocument in openWindowDocuments) {
        SEBBrowserWindow *browserWindow = (SEBBrowserWindow *)openWindowDocument.mainWindowController.window;
        if (browserWindow != self.mainBrowserWindow) {
            [self closeWebView:browserWindow.webView];
        }
    }
}


#pragma mark SEB Dock Buttons Action Methods

- (void) restartDockButtonPressed
{
    NSUserDefaults *preferences = [NSUserDefaults standardUserDefaults];
    
    // Close all browser windows (documents)
    [self closeAllAdditionalBrowserWindows];
    
    if ([preferences secureBoolForKey:@"org_safeexambrowser_SEB_restartExamUseStartURL"]) {
        // Load start URL from the system's user defaults
        NSString *urlText = [preferences secureStringForKey:@"org_safeexambrowser_SEB_startURL"];
        DDLogInfo(@"Reloading Start URL in main browser window: %@", urlText);
        [self openURLString:urlText withSEBUserAgentInWebView:self.webView];
    } else {
        NSString* restartExamURL = [preferences secureStringForKey:@"org_safeexambrowser_SEB_restartExamURL"];
        if (restartExamURL.length > 0) {
            // Load restart exam URL into the main browser window
            DDLogInfo(@"Reloading Restart Exam URL in main browser window: %@", restartExamURL);
            [self openURLString:restartExamURL withSEBUserAgentInWebView:self.webView];
        }
    }
}


- (void) reloadDockButtonPressed
{
    DDLogInfo(@"Reloading current browser window: %@", self.activeBrowserWindow);
    [self.activeBrowserWindow.webView reload:self.activeBrowserWindow];
}


@end
