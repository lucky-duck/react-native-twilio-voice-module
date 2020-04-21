#import <React/RCTBridgeModule.h>
#import <React/RCTEventEmitter.h>
@import PushKit;

@interface TwilioVoiceModule : RCTEventEmitter <RCTBridgeModule>

+ (instancetype)sharedInstance;
+ (id) allocWithZone:(NSZone *)zone;
- (void) fetchAccessToken;
- (void) credentialsUpdated:(PKPushCredentials*)credentials;
- (void) credentialsInvalidated;
- (void) incomingPushReceived:(PKPushPayload*)payload withCompletionHandler:(void (^)(void))completion;

@end
