//
//  SceneDelegate.m
//  Moonlight
//

#import "SceneDelegate.h"
#import "AppDelegate.h"

#import "Moonlight-Swift.h"

@implementation SceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    if (![scene isKindOfClass:[UIWindowScene class]]) {
        return;
    }

    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene*)scene];
    // The interface is SwiftUI (see Limelight/SwiftUI)
    self.window.rootViewController = [MLRootFactory makeRootViewController];

    // Code that predates scenes reaches the window through the app delegate
    AppDelegate* appDelegate = (AppDelegate*)UIApplication.sharedApplication.delegate;
    appDelegate.window = self.window;

#if !TARGET_OS_TV
    UIApplicationShortcutItem* shortcut = connectionOptions.shortcutItem;
    if (shortcut != nil) {
        appDelegate.pcUuidToLoad = (NSString*)[shortcut.userInfo objectForKey:@"UUID"];
    }
#endif

    [self.window makeKeyAndVisible];
}

#if !TARGET_OS_TV
- (void)windowScene:(UIWindowScene *)windowScene performActionForShortcutItem:(UIApplicationShortcutItem *)shortcutItem completionHandler:(void (^)(BOOL))completionHandler {
    AppDelegate* appDelegate = (AppDelegate*)UIApplication.sharedApplication.delegate;
    appDelegate.pcUuidToLoad = (NSString*)[shortcutItem.userInfo objectForKey:@"UUID"];
    appDelegate.shortcutCompletionHandler = completionHandler;
}
#endif

@end
