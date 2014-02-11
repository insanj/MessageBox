//
//  SpringBoard.xm
//  MessageBox
//
//  Created by Adam Bell on 2014-02-04.
//  Copyright (c) 2014 Adam Bell. All rights reserved.
//

#import "messagebox.h"
#import "MBChatHeadWindow.h"

/**
 * SpringBoard Hooks
 *
 */

static MBChatHeadWindow *_chatHeadWindow;
static BKSProcessAssertion *_keepAlive;

%group SpringBoardHooks

static void fbDidTapChatHead(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    SBIconController *iconController = [%c(SBIconController) sharedInstance];

    //If icons are wiggling and a chat head is tapped, stop the wiggling
    if (iconController.isEditing)
        [iconController setIsEditing:NO];
}

static void fbLaunching(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    [[%c(SBUIController) sharedInstance] mb_removeChatHeadWindow];
}

static void fbQuitting(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    [[%c(SBUIController) sharedInstance] mb_addChatHeadWindow];
}

%hook SBUIController

//Stack up the chat heads when the home button is pressed

- (BOOL)clickedMenuButton {
    //To keep in app as stock as possible, don't intercept the home button when the app is active
    //So only take action if FB is active but in the background
    if ([_keepAlive valid]) {
        notify_post("ca.adambell.messagebox.fbResignChatHeads");
    }

    return %orig;
}

- (BOOL)handleMenuDoubleTap {
    if ([_keepAlive valid]) {
        notify_post("ca.adambell.messagebox.fbResignChatHeads");
    }

    return %orig;
}

%new
- (void)mb_addChatHeadWindow {
    int facebookPID = PIDForProcessNamed(@"Paper");
    if (facebookPID == 0)
        return;

    if (_keepAlive != nil)
        [_keepAlive invalidate];

    _keepAlive = [[%c(BKSProcessAssertion) alloc] initWithPID:facebookPID
                                                   flags:(ProcessAssertionFlagPreventSuspend |
                                                          ProcessAssertionFlagAllowIdleSleep |
                                                          ProcessAssertionFlagPreventThrottleDownCPU |
                                                          ProcessAssertionFlagWantsForegroundResourcePriority)
                                                  reason:kProcessAssertionReasonBackgroundUI
                                                    name:@"epichax"
                                             withHandler:^void (void)
                 {
                     DebugLog(@"FACEBOOK PID: %d kept alive: %@", facebookPID, [_keepAlive valid] > 0 ? @"TRUE" : @"FALSE");
                 }];

    SBApplication *facebookApplication = [[%c(SBApplicationController) sharedInstance] applicationWithDisplayIdentifier:@"com.facebook.Paper"];

    SBWindowContextHostManager *contextHostManager = [facebookApplication mainScreenContextHostManager];

    SBWindowContextHostWrapperView *facebookHostView = [contextHostManager hostViewForRequester:@"hax" enableAndOrderFront: YES];
    facebookHostView.backgroundColorWhileNotHosting = [UIColor clearColor];
    facebookHostView.backgroundColorWhileHosting = [UIColor clearColor];

    for (UIView *subview in facebookHostView.subviews) {
        subview.backgroundColor = [UIColor clearColor];
    }

    for (UIView *subview in [_chatHeadWindow.subviews copy]) {
        [subview removeFromSuperview];
    }

    [_chatHeadWindow addSubview:facebookHostView];

    _chatHeadWindow.alpha = 0.0;

    [UIView animateWithDuration:0.4
                          delay:0.5
                        options:0
                     animations:^{
                            _chatHeadWindow.alpha = 1.0;
                        }
                     completion:nil];

}

%new
- (void)mb_removeChatHeadWindow {
    if (_keepAlive != nil) {
        // Kill the BKSProcessAssertion because it isn't needed anymore
        // Not sure if creating / removing it is necessary but I'd like to keep it as stock as possible when in app)

        [_keepAlive invalidate];
        _keepAlive = nil;

        SBApplication *facebookApplication = [[%c(SBApplicationController) sharedInstance] applicationWithDisplayIdentifier:@"com.facebook.Paper"];

        SBWindowContextHostManager *contextHostManager = [facebookApplication mainScreenContextHostManager];

        [contextHostManager disableHostingForRequester:@"hax"];

        for (UIView *subview in [[MBChatHeadWindow sharedInstance].subviews copy]) {
            [subview removeFromSuperview];
        }

        _chatHeadWindow.alpha = 0.0;
    }
}

%end

%hook UIWindow

- (void)makeKeyAndVisible {
    %orig;

    if (self != _chatHeadWindow) {
        if (_chatHeadWindow == nil) {
            _chatHeadWindow = [MBChatHeadWindow sharedInstance];
            _chatHeadWindow.backgroundColor = [UIColor clearColor];
        }

        _chatHeadWindow.windowLevel = 10; //1 below UIKeyboard //UIWindowLevelStatusBar;
        _chatHeadWindow.hidden = NO;
        _chatHeadWindow.backgroundColor = [UIColor clearColor];
    }
}

%end

%end