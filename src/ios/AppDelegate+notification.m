//
//  AppDelegate+notification.m
//  pushtest
//
//  Created by Robert Easterday on 10/26/12.
//
//

#import "AppDelegate+notification.h"
#import "PushPlugin.h"
#import <objc/runtime.h>
#import <Applozic/Applozic.h>

#define SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(v)  ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] != NSOrderedAscending)
#define SYSTEM_VERSION_LESS_THAN(v) ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedAscending)

static char launchNotificationKey;
static char coldstartKey;

@implementation AppDelegate (notification)

- (id) getCommandInstance:(NSString*)className
{
    return [self.viewController getCommandInstance:className];
}

// its dangerous to override a method from within a category.
// Instead we will use method swizzling. we set this up in the load call.
+ (void)load
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class class = [self class];

        SEL originalSelector = @selector(init);
        SEL swizzledSelector = @selector(pushPluginSwizzledInit);

        Method original = class_getInstanceMethod(class, originalSelector);
        Method swizzled = class_getInstanceMethod(class, swizzledSelector);

        BOOL didAddMethod =
        class_addMethod(class,
                        originalSelector,
                        method_getImplementation(swizzled),
                        method_getTypeEncoding(swizzled));

        if (didAddMethod) {
            class_replaceMethod(class,
                                swizzledSelector,
                                method_getImplementation(original),
                                method_getTypeEncoding(original));
        } else {
            method_exchangeImplementations(original, swizzled);
        }
    });
}

- (AppDelegate *)pushPluginSwizzledInit
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(createNotificationChecker:)
                                                 name:UIApplicationDidFinishLaunchingNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter]addObserver:self
                                            selector:@selector(pushPluginOnApplicationDidBecomeActive:)
                                                name:UIApplicationDidBecomeActiveNotification
                                              object:nil];

    // This actually calls the original init method over in AppDelegate. Equivilent to calling super
    // on an overrided method, this is not recursive, although it appears that way. neat huh?
    return [self pushPluginSwizzledInit];
}

// This code will be called immediately after application:didFinishLaunchingWithOptions:. We need
// to process notifications in cold-start situations
- (void)createNotificationChecker:(NSNotification *)notification
{
    NSLog(@"createNotificationChecker");
    if (notification)
    {
        NSDictionary *launchOptions = [notification userInfo];
        if (launchOptions) {
            NSLog(@"coldstart");
            self.launchNotification = [launchOptions objectForKey: @"UIApplicationLaunchOptionsRemoteNotificationKey"];
            self.coldstart = [NSNumber numberWithBool:YES];
        } else {
            NSLog(@"not coldstart");
            self.coldstart = [NSNumber numberWithBool:NO];
        }
    }
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    [ALRegisterUserClientService isAppUpdated];
    [self registerForNotification];
    ALAppLocalNotifications *localNotification = [ALAppLocalNotifications appLocalNotificationHandler];
    [localNotification dataConnectionNotificationHandler];

    NSLog(@"launchOptions: %@", launchOptions);

    if (launchOptions != nil)
    {
        NSDictionary *dictionary = [launchOptions objectForKey:UIApplicationLaunchOptionsRemoteNotificationKey];
        if (dictionary != nil)
        {
            NSLog(@"Launched from push notification: %@", dictionary);
            ALPushNotificationService *pushNotificationService = [[ALPushNotificationService alloc] init];
            BOOL applozicProcessed = [pushNotificationService processPushNotification:dictionary
                                                                             updateUI:[NSNumber numberWithInt:APP_STATE_INACTIVE]];

            if (!applozicProcessed) {
                //Note: notification for app
            }
        }
    }
    return [super application:application didFinishLaunchingWithOptions:launchOptions];
}
- (void)application:(UIApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken {
    PushPlugin *pushHandler = [self getCommandInstance:@"PushNotification"];
    [pushHandler didRegisterForRemoteNotificationsWithDeviceToken:deviceToken];
    NSLog(@"DEVICE_TOKEN :: %@", deviceToken);

    const unsigned *tokenBytes = [deviceToken bytes];
    NSString *hexToken = [NSString stringWithFormat:@"%08x%08x%08x%08x%08x%08x%08x%08x",
                          ntohl(tokenBytes[0]), ntohl(tokenBytes[1]), ntohl(tokenBytes[2]),
                          ntohl(tokenBytes[3]), ntohl(tokenBytes[4]), ntohl(tokenBytes[5]),
                          ntohl(tokenBytes[6]), ntohl(tokenBytes[7])];

    NSString *apnDeviceToken = hexToken;
    NSLog(@"APN_DEVICE_TOKEN :: %@", hexToken);

    if ([[ALUserDefaultsHandler getApnDeviceToken] isEqualToString:apnDeviceToken])
    {
        return;
    }

    ALRegisterUserClientService *registerUserClientService = [[ALRegisterUserClientService alloc] init];
    [registerUserClientService updateApnDeviceTokenWithCompletion:apnDeviceToken withCompletion:^(ALRegistrationResponse *rResponse, NSError *error) {

        if (error)
        {
            NSLog(@"REGISTRATION ERROR :: %@",error.description);
            return;
        }

        NSLog(@"Registration response from server : %@", rResponse);
    }];
}

- (void)application:(UIApplication *)application didFailToRegisterForRemoteNotificationsWithError:(NSError *)error {
    PushPlugin *pushHandler = [self getCommandInstance:@"PushNotification"];
    [pushHandler didFailToRegisterForRemoteNotificationsWithError:error];
}

- (void) application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo {
    NSLog(@"clicked on the shade");
      ALPushNotificationService *pushNotificationService = [[ALPushNotificationService alloc] init];
     if([pushNotificationService isApplozicNotification:userInfo]){
         [pushNotificationService notificationArrivedToApplication:application withDictionary:userInfo];
     }else{
      PushPlugin *pushHandler = [self getCommandInstance:@"PushNotification"];
      pushHandler.notificationMessage = userInfo;
      pushHandler.isInline = NO;
      [pushHandler notificationReceived];
    }
}

- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo fetchCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler {
    NSLog(@"didReceiveNotification with fetchCompletionHandler");

      ALPushNotificationService *pushNotificationService = [[ALPushNotificationService alloc] init];
         if([pushNotificationService isApplozicNotification:userInfo]){
           [pushNotificationService notificationArrivedToApplication:application withDictionary:userInfo];
           completionHandler(UIBackgroundFetchResultNewData);
         }else{
    // app is in the foreground so call notification callback
    if (application.applicationState == UIApplicationStateActive) {
        NSLog(@"app active");
        PushPlugin *pushHandler = [self getCommandInstance:@"PushNotification"];
        pushHandler.notificationMessage = userInfo;
        pushHandler.isInline = YES;
        [pushHandler notificationReceived];

        completionHandler(UIBackgroundFetchResultNewData);
    }
    // app is in background or in stand by
    else {
        NSLog(@"app in-active");

        // do some convoluted logic to find out if this should be a silent push.
        long silent = 0;
        id aps = [userInfo objectForKey:@"aps"];
        id contentAvailable = [aps objectForKey:@"content-available"];
        if ([contentAvailable isKindOfClass:[NSString class]] && [contentAvailable isEqualToString:@"1"]) {
            silent = 1;
        } else if ([contentAvailable isKindOfClass:[NSNumber class]]) {
            silent = [contentAvailable integerValue];
        }

        if (silent == 1) {
            NSLog(@"this should be a silent push");
            void (^safeHandler)(UIBackgroundFetchResult) = ^(UIBackgroundFetchResult result){
                dispatch_async(dispatch_get_main_queue(), ^{
                    completionHandler(result);
                });
            };

            PushPlugin *pushHandler = [self getCommandInstance:@"PushNotification"];

            if (pushHandler.handlerObj == nil) {
                pushHandler.handlerObj = [NSMutableDictionary dictionaryWithCapacity:2];
            }

            id notId = [userInfo objectForKey:@"notId"];
            if (notId != nil) {
                NSLog(@"Push Plugin notId %@", notId);
                [pushHandler.handlerObj setObject:safeHandler forKey:notId];
            } else {
                NSLog(@"Push Plugin notId handler");
                [pushHandler.handlerObj setObject:safeHandler forKey:@"handler"];
            }

            pushHandler.notificationMessage = userInfo;
            pushHandler.isInline = NO;
            [pushHandler notificationReceived];
        } else {
            NSLog(@"just put it in the shade");
            //save it for later
            self.launchNotification = userInfo;

            completionHandler(UIBackgroundFetchResultNewData);
        }
    }
  }
}

- (BOOL)userHasRemoteNotificationsEnabled {
    UIApplication *application = [UIApplication sharedApplication];
    if ([[UIApplication sharedApplication] respondsToSelector:@selector(registerUserNotificationSettings:)]) {
        return application.currentUserNotificationSettings.types != UIUserNotificationTypeNone;
    } else {
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
        return application.enabledRemoteNotificationTypes != UIRemoteNotificationTypeNone;
#pragma GCC diagnostic pop
    }
}

- (void)pushPluginOnApplicationDidBecomeActive:(NSNotification *)notification {

    NSLog(@"active");

    UIApplication *application = notification.object;

    PushPlugin *pushHandler = [self getCommandInstance:@"PushNotification"];
    if (pushHandler.clearBadge) {
        NSLog(@"PushPlugin clearing badge");
        //zero badge
        application.applicationIconBadgeNumber = 0;
    } else {
        NSLog(@"PushPlugin skip clear badge");
    }

    if (self.launchNotification) {
        pushHandler.isInline = NO;
        pushHandler.coldstart = [self.coldstart boolValue];
        pushHandler.notificationMessage = self.launchNotification;
        self.launchNotification = nil;
        self.coldstart = [NSNumber numberWithBool:NO];
        [pushHandler performSelectorOnMainThread:@selector(notificationReceived) withObject:pushHandler waitUntilDone:NO];
    }
}


- (void)application:(UIApplication *) application handleActionWithIdentifier: (NSString *) identifier
forRemoteNotification: (NSDictionary *) notification completionHandler: (void (^)()) completionHandler {

    NSLog(@"Push Plugin handleActionWithIdentifier %@", identifier);
    NSMutableDictionary *userInfo = [notification mutableCopy];
    [userInfo setObject:identifier forKey:@"actionCallback"];
    NSLog(@"Push Plugin userInfo %@", userInfo);

    if (application.applicationState == UIApplicationStateActive) {
        PushPlugin *pushHandler = [self getCommandInstance:@"PushNotification"];
        pushHandler.notificationMessage = userInfo;
        pushHandler.isInline = NO;
        [pushHandler notificationReceived];
    } else {
        void (^safeHandler)() = ^(void){
            dispatch_async(dispatch_get_main_queue(), ^{
                completionHandler();
            });
        };

        PushPlugin *pushHandler = [self getCommandInstance:@"PushNotification"];

        if (pushHandler.handlerObj == nil) {
            pushHandler.handlerObj = [NSMutableDictionary dictionaryWithCapacity:2];
        }

        id notId = [userInfo objectForKey:@"notId"];
        if (notId != nil) {
            NSLog(@"Push Plugin notId %@", notId);
            [pushHandler.handlerObj setObject:safeHandler forKey:notId];
        } else {
            NSLog(@"Push Plugin notId handler");
            [pushHandler.handlerObj setObject:safeHandler forKey:@"handler"];
        }

        pushHandler.notificationMessage = userInfo;
        pushHandler.isInline = NO;

        [pushHandler performSelectorOnMainThread:@selector(notificationReceived) withObject:pushHandler waitUntilDone:NO];
    }
}

- (void)applicationDidEnterBackground:(UIApplication *)application {

    NSLog(@"APP_ENTER_IN_BACKGROUND");
    [[NSNotificationCenter defaultCenter] postNotificationName:@"APP_ENTER_IN_BACKGROUND" object:nil];
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
    [ALPushNotificationService applicationEntersForeground];

    NSLog(@"APP_ENTER_IN_FOREGROUND");
    [[NSNotificationCenter defaultCenter] postNotificationName:@"APP_ENTER_IN_FOREGROUND" object:nil];
    [application setApplicationIconBadgeNumber:0];
}

- (void)applicationWillTerminate:(UIApplication *)application {
    [[ALDBHandler sharedInstance] saveContext];
}

// The accessors use an Associative Reference since you can't define a iVar in a category
// http://developer.apple.com/library/ios/#documentation/cocoa/conceptual/objectivec/Chapters/ocAssociativeReferences.html
- (NSMutableArray *)launchNotification
{
    return objc_getAssociatedObject(self, &launchNotificationKey);
}

- (void)setLaunchNotification:(NSDictionary *)aDictionary
{
    objc_setAssociatedObject(self, &launchNotificationKey, aDictionary, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (NSNumber *)coldstart
{
    return objc_getAssociatedObject(self, &coldstartKey);
}

- (void)setColdstart:(NSNumber *)aNumber
{
    objc_setAssociatedObject(self, &coldstartKey, aNumber, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)dealloc
{
    self.launchNotification = nil; // clear the association and release the object
    self.coldstart = nil;
}

-(void)registerForNotification
{
    if(SYSTEM_VERSION_LESS_THAN(@"10.0"))
    {
        [[UIApplication sharedApplication] registerUserNotificationSettings:[UIUserNotificationSettings settingsForTypes:(UIUserNotificationTypeSound |    UIUserNotificationTypeAlert | UIUserNotificationTypeBadge) categories:nil]];

        [[UIApplication sharedApplication] registerForRemoteNotifications];
    }
    else
    {
        UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
        center.delegate = self;
        [center requestAuthorizationWithOptions:(UNAuthorizationOptionSound | UNAuthorizationOptionAlert | UNAuthorizationOptionBadge) completionHandler:^(BOOL granted, NSError * _Nullable error)
         {
             if(!error)
             {
                 dispatch_async(dispatch_get_main_queue(), ^ {
                     [[UIApplication sharedApplication] registerForRemoteNotifications];  // required to get the app to do anything at all about push notifications
                     NSLog(@"Push registration success." );
                 });
             }
             else
             {
                 NSLog(@"Push registration FAILED" );
                 NSLog(@"ERROR: %@ - %@", error.localizedFailureReason, error.localizedDescription );
                 NSLog(@"SUGGESTIONS: %@ - %@", error.localizedRecoveryOptions, error.localizedRecoverySuggestion );
             }
         }];
    }
}

@end
