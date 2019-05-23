#import "Tweak.h"

#ifndef SIMULATOR
HBPreferences *preferences;
#endif

BOOL enabled;


%group PanCake

UIPanGestureRecognizer *panGestureRecognizer;
// UINavigationController *lastNavVC;

BOOL shouldRecognizeSimultaneousGestures;


static BOOL panGestureIsSwipingLeftToRight(UIPanGestureRecognizer *panGest) {
    CGPoint velocity = [panGestureRecognizer velocityInView:panGest.view];

    DLog(@"panGestureIsSwipingLeftToRight %@", NSStringFromCGPoint(velocity));
    if (fabs(velocity.x) > fabs(velocity.y)) { //horizontal
        if (velocity.x > 0) { //from left to right
            return YES;
        }
    }

    return NO;
}


%hook UINavigationController

-(void)_layoutTopViewController {
    %orig;

    UIViewController *viewController = [self topViewController];

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"

    UIView *viewForGesture = viewController.view;

    if (!viewForGesture) return;
    
    if (viewController != [viewController.navigationController.viewControllers objectAtIndex:0]) { //if it's not rootviewcontroller
        if (![viewForGesture.gestureRecognizers containsObject:panGestureRecognizer]) {
            DLog(@"Adding gesture on view : %@", self._cachedInteractionController);

            if ([self._cachedInteractionController respondsToSelector:@selector(handleNavigationTransition:)]) {
                panGestureRecognizer = [[UIPanGestureRecognizer alloc]initWithTarget:self._cachedInteractionController action:@selector(handleNavigationTransition:)];
                panGestureRecognizer.delegate = self;
                [viewForGesture addGestureRecognizer:panGestureRecognizer];
            }
        }
    }
    
#pragma clang diagnostic pop
}

//Limit conflicts with some UIScrollView and swipes from right to left
%new
- (BOOL)gestureRecognizerShouldBegin:(UIPanGestureRecognizer *)panGestureRecognizer {
    return panGestureIsSwipingLeftToRight(panGestureRecognizer);
}

%new
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    DLog(@"gestureRecognizer");

    if (shouldRecognizeSimultaneousGestures) {
        if (gestureRecognizer == panGestureRecognizer) {
            return panGestureIsSwipingLeftToRight(panGestureRecognizer); //Messenger app requires this additional check (swiping side)
        }
    }

    return NO;
}

-(void)_finishInteractiveTransition:(double)arg1 transitionContext:(id)arg2 {
    %orig;

    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
}

%end //hook UINavigationController


%hook _UINavigationInteractiveTransitionBase

-(void)handleNavigationTransition:(UIPanGestureRecognizer*)arg1 {
    DLog(@"handleNavigationTransition %@", arg1);

    %orig;
}

%end //hook _UINavigationInteractiveTransitionBase

%end //group PanCake


// %group SpotifySpecialHandling

//TODO

// %end //group SpotifySpecialHandling


void setDefaultBlacklistedApps() {
    NSArray* defaultBlacklistedApp = @[
        //already natively implemented
        @"com.atebits.Tweetie2",
        @"com.burbn.instagram",
        @"com.facebook.Facebook",
        @"com.christianselig.Apollo",
        @"ph.telegra.Telegraph",

        //gesture conflicts
        @"com.spotify.client" //adding song to the queue
    ];

    NSFileManager *fileManager = [NSFileManager defaultManager];
    if(![fileManager fileExistsAtPath:PLIST_FILE]) { //only on first install
        DLog(@"PLIST_FILE doesn't exists");

        NSMutableDictionary *plistDict = [[NSMutableDictionary alloc] init];

        for (NSString *blacklistedApp in defaultBlacklistedApp) {
            DLog(@"blacklisting app %@", blacklistedApp);
            [plistDict setValue:@"YES" forKey:blacklistedApp];
        }

        [plistDict writeToFile:PLIST_FILE atomically:YES];
    }
}

BOOL appIsBlacklisted(NSString *appName) {
    return pref_getBool(appName) || !enabled;
}


%ctor {
    preferences = [[HBPreferences alloc] initWithIdentifier:@"com.anthopak.pancake"];
    [preferences registerBool:&enabled default:YES forKey:@"enabled"];
    setDefaultBlacklistedApps();

    NSString *appName = [[NSBundle mainBundle] bundleIdentifier];
    if (appName && !appIsBlacklisted(appName)) {
        DLog(@"PanCake: Hooking app %@", appName);

        if ([appName isEqualToString:@"com.apple.MobileSMS"] || [appName isEqualToString:@"com.facebook.Messenger"]) {
            shouldRecognizeSimultaneousGestures = YES;
        }

        %init(PanCake);
    }
}
