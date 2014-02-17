//
//  Facebook.xm
//  MessageBox
//
//  Created by Adam Bell on 2014-02-04.
//  Copyright (c) 2014 Adam Bell. All rights reserved.
//

#import "messagebox.h"

#define KEYBOARD_WINDOW_LEVEL 1003.0f

static FBApplicationController *_applicationController;
static FBMessengerModule *_messengerModule;

static BOOL _shouldShowPublisherBar = NO;

static BOOL _ignoreBackgroundedNotifications = YES;

static BOOL _UIHiddenForMessageBox;

/**
 * Facebook Hooks
 *
 */
%group FacebookHooks

static void fbResignChatHeads(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    FBApplicationController *controller = [%c(FBApplicationController) mb_sharedInstance];
    [controller.messengerModule.chatHeadViewController resignChatHeadViews];
    [[UIApplication sharedApplication].keyWindow endEditing:YES];
}

static void fbForceActive(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    _ignoreBackgroundedNotifications = YES;
    FBApplicationController *controller = [%c(FBApplicationController) mb_sharedInstance];
    [controller.messengerModule.moduleSession enteredForeground];
}

static void fbForceBackgrounded(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    _ignoreBackgroundedNotifications = NO;
    [[NSNotificationCenter defaultCenter] postNotificationName:UIApplicationDidEnterBackgroundNotification object:nil userInfo:nil];
}


// Keyboards also need to be shown when the app is backgrounded
%hook UITextEffectsWindow

- (void)setKeepContextInBackground:(BOOL)keepContext {
    %orig(YES);
}

- (BOOL)keepContextInBackground {
    return YES;
}

// Paper does some weird shit with window levels... no u
- (CGFloat)windowLevel {
    return KEYBOARD_WINDOW_LEVEL;
}

- (void)setWindowLevel:(CGFloat)windowLevel {
    %orig(KEYBOARD_WINDOW_LEVEL);
}

%end

// Need to force the app to believe it's still active... no notifications for you! >:D
%hook NSNotificationCenter

- (void)postNotificationName:(NSString *)notificationName object:(id)notificationSender userInfo:(NSDictionary *)userInfo {
    NSString *notification = [notificationName lowercaseString];
    if ([notification rangeOfString:@"background"].location != NSNotFound && _ignoreBackgroundedNotifications) {
        notify_post("ca.adambell.messagebox.fbQuitting");

        [[UIApplication sharedApplication].keyWindow endEditing:YES];

        FBApplicationController *controller = [%c(FBApplicationController) mb_sharedInstance];
        [controller mb_setUIHiddenForMessageBox:YES];

        return;
    }

    DebugLog(@"Notification Posted: %@ object: %@ userInfo: %@", notificationName, notificationSender, userInfo);

    %orig;
}

%end

%hook UIApplication

- (UIApplicationState)applicationState {
    if (_ignoreBackgroundedNotifications)
        return UIApplicationStateActive;
    else
        return %orig;
}

%end

%hook AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    BOOL didFinishLaunching = %orig;

    for (UIWindow *window in application.windows) {
        [window setKeepContextInBackground:YES];
    }

    return didFinishLaunching;
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    notify_post("ca.adambell.messagebox.fbLaunching");
    DebugLog(@"FACEBOOK OPENING RIGHT NOW");

    FBApplicationController *controller = [%c(FBApplicationController) mb_sharedInstance];
    [controller mb_setUIHiddenForMessageBox:NO];

    %orig;
}

%end

%hook FBApplicationController

- (id)initWithSession:(id)session {
    _applicationController = %orig;
    return _applicationController;
}

%new
+ (id)mb_sharedInstance {
    return _applicationController;
}

%new
- (void)mb_setUIHiddenForMessageBox:(BOOL)hidden {
    _UIHiddenForMessageBox = hidden;

    [[UIApplication sharedApplication].keyWindow setKeepContextInBackground:hidden];

    [UIApplication sharedApplication].keyWindow.backgroundColor = hidden ? [UIColor clearColor] : [UIColor blackColor];

    FBChatHeadViewController *chatHeadController = self.messengerModule.chatHeadViewController;
    [chatHeadController resignChatHeadViews];
    [chatHeadController setHasInboxChatHead:hidden];

    FBStackView *stackView = (FBStackView *)chatHeadController.view;
    UIView *chatHeadContainerView = stackView;

    while (![stackView isKindOfClass:%c(FBStackView)]) {
        if (stackView.superview == nil)
            break;

        chatHeadContainerView = stackView;
        stackView = (FBStackView *)stackView.superview;
    }

    for (UIView *view in stackView.subviews) {
        if (view != chatHeadContainerView && ![view isKindOfClass:%c(FBDimmingView)])
            view.hidden = hidden;
    }

    // Account for status bar
    CGRect chatHeadWindowFrame = [UIScreen mainScreen].bounds;
    if (hidden) {
        chatHeadWindowFrame.origin.y += 20.0;
        chatHeadWindowFrame.size.height -= 20.0;
    }

    [UIApplication sharedApplication].keyWindow.frame = chatHeadWindowFrame;

    _shouldShowPublisherBar = hidden;
}

%new
- (void)mb_openURL:(NSURL *)url {
    CPDistributedMessagingCenter *sbMessagingCenter = [%c(CPDistributedMessagingCenter) centerNamed:@"ca.adambell.MessageBox.sbMessagingCenter"];
    rocketbootstrap_distributedmessagingcenter_apply(sbMessagingCenter);

    [sbMessagingCenter sendMessageName:@"messageboxOpenURL" userInfo:@{ @"url" : [url absoluteString] }];

    FBChatHeadViewController *chatHeadController = self.messengerModule.chatHeadViewController;
    [chatHeadController resignChatHeadViews];
}

%new
- (void)mb_forceRotationToInterfaceOrientation:(UIInterfaceOrientation)orientation {
    DebugLog(@"NEXT ORIENTATION: %d", orientation);

    // Popover blows up when rotated
    FBChatHeadViewController *chatHeadController = self.messengerModule.chatHeadViewController;
    [chatHeadController resignChatHeadViews];

    [[UIApplication sharedApplication] setStatusBarOrientation:orientation];

    for (UIWindow *window in [[UIApplication sharedApplication] windows]) {
        [window _setRotatableViewOrientation:orientation
                                    duration:0.0
                                       force:YES];
    }

    /*
     Some crazy UIKeyboard hacks because for some reason UIKeyboard has a seizure when a suspended app tries to rotate...

     if orientation == 1
     revert to identity matrix
     if orientation == 2
     flip keyboard PI
     if orientation == 3
     flip keyboard PI/2 RAD
     set frame & bounds to screen size
     if orientation == 4
     flip keyboard -PI/2 RAD
     set frame & bounds to screen size
     */

    UITextEffectsWindow *keyboardWindow = [UITextEffectsWindow sharedTextEffectsWindow];

    switch (orientation) {
        case UIInterfaceOrientationPortrait: {
            keyboardWindow.transform = CGAffineTransformIdentity;
            break;
        }
        case UIInterfaceOrientationPortraitUpsideDown: {
            keyboardWindow.transform = CGAffineTransformMakeRotation(M_PI);
            break;
        }
        case UIInterfaceOrientationLandscapeLeft: {
            keyboardWindow.transform = CGAffineTransformMakeRotation(-M_PI / 2);
            keyboardWindow.bounds = [[UIScreen mainScreen] bounds];
            keyboardWindow.frame = keyboardWindow.bounds;
            break;
        }
        case UIInterfaceOrientationLandscapeRight: {
            keyboardWindow.transform = CGAffineTransformMakeRotation(M_PI / 2);
            keyboardWindow.bounds = [[UIScreen mainScreen] bounds];
            keyboardWindow.frame = keyboardWindow.bounds;
            break;
        }
        default:
            break;
    }
}

%end

%hook FBMInboxViewController

- (void)viewWillAppear:(BOOL)animated {
    %orig;

    self.inboxView.showPublisherBar = 0;
}

%end

%hook FBMInboxView

- (void)setShowPublisherBar:(BOOL)showPublisherBar {
    %orig([self mb_shouldShowPublisherBar]);
}

%new
- (BOOL)mb_shouldShowPublisherBar {
    return _shouldShowPublisherBar;
}

%end

%hook FBChatHeadSurfaceView

- (void)setCurrentLayout:(FBChatHeadLayout *)currentLayout {
    CPDistributedMessagingCenter *sbMessagingCenter = [%c(CPDistributedMessagingCenter) centerNamed:@"ca.adambell.MessageBox.sbMessagingCenter"];
    rocketbootstrap_distributedmessagingcenter_apply(sbMessagingCenter);
    [sbMessagingCenter sendMessageName:@"messageboxUpdateChatHeadsState" userInfo:@{ @"opened" : @(currentLayout == self.openedLayout) }];

    %orig;
}

%end

%hook MessagesViewController

- (void)messageCell:(id)arg1 didSelectURL:(NSURL *)url {
    if (_UIHiddenForMessageBox && [url isKindOfClass:[NSURL class]] && url != nil) {
        FBApplicationController *applicationController = [%c(FBApplicationController) mb_sharedInstance];
        [applicationController mb_openURL:url];
    }
    else {
        %orig;
    }
}

%end

%end
