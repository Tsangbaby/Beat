#pragma once
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

// Declarations only: do not define replacement Swift classes with system names.
// The supplied reconstruction does not establish device-side ABI compatibility.
NS_ASSUME_NONNULL_BEGIN

@interface SpringBoard : UIApplication
@end

@interface SBApplication : NSObject
@property (nonatomic, readonly, copy) NSString *bundleIdentifier;
- (void)launchSuspended;
@end

@interface SBApplicationController : NSObject
+ (instancetype)sharedInstance NS_SWIFT_NAME(sharedInstance());
- (nullable SBApplication *)applicationWithBundleIdentifier:(NSString *)bundleID
    NS_SWIFT_NAME(application(withBundleIdentifier:));
@end

@interface SBIcon : NSObject
@property (nonatomic, readonly, copy, nullable) NSString *applicationBundleID;
@end

@interface SBIconView : UIView
@property (nonatomic, readonly, nullable) SBIcon *icon;
@end

@interface SBIconController : NSObject
@end
@interface _SBFluidSwitcherPanGestureRecognizer : UIPanGestureRecognizer
@end
@interface SBGrabberTongue : UIView
@end

@interface SBFZStackParticipant : NSObject
@property (nonatomic) BOOL ownsHomeGesture;
@property (nonatomic) NSInteger activationState;
@end

@interface SBFluidSwitcherGestureManager : NSObject
@end

@interface FBScene : NSObject
@property (nonatomic, readonly, copy) NSString *identifier;
@end
@interface FBSceneManager : NSObject
@end
@interface FBSystemService : NSObject
@end
@interface SBMainDisplaySceneManager : NSObject
@end
@interface UIApplicationSceneDeactivationManager : NSObject
@end
@interface BNContentViewController : UIViewController
@end
@interface SBDeviceApplicationSceneViewController : UIViewController
@end
@interface UIStatusBarWindow : UIWindow
@end

@interface LSApplicationProxy : NSObject
- (nullable NSString *)applicationIdentifier;
- (nullable NSString *)localizedName;
- (BOOL)isLaunchProhibited;
- (BOOL)isWebApplication;
@end

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace NS_SWIFT_NAME(default());
- (void)enumerateApplicationsOfType:(NSInteger)type
                            block:(void (^)(LSApplicationProxy *proxy))block
    NS_SWIFT_NAME(enumerateApplications(ofType:block:));
@end

NS_ASSUME_NONNULL_END
