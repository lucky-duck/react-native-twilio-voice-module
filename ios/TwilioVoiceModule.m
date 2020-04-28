#import "TwilioVoiceModule.h"

#import <AFNetworking/AFNetworking.h>
#import <CallKit/CallKit.h>
@import PushKit;
@import TwilioVoice;

static NSString *const kAccessTokenUrl = @"http://stepintocity-server.herokuapp.com/twilio/accessToken";
static NSString *const StatePending = @"PENDING";
static NSString *const StateConnecting = @"CONNECTING";
static NSString *const StateConnected = @"CONNECTED";
static NSString *const StateRinging = @"RINGING";
static NSString *const StateReconnecting = @"RECONNECTING";
static NSString *const StateDisconnected = @"DISCONNECTED";
// static NSString *const kYourServerBaseURLString = @"https://orchid-fox-2429.twil.io";
static NSString *const kYourServerBaseURLString = @"https://tomato-reindeer-1763.twil.io";
// If your token server is written in PHP, kAccessTokenEndpoint needs .php extension at the end. For example : /accessToken.php
static NSString *const kAccessTokenEndpoint = @"/access-token";
NSString * const kCachedDeviceToken = @"CachedDeviceToken";

API_AVAILABLE(ios(8.0))
@interface TwilioVoiceModule()<TVOCallDelegate, TVONotificationDelegate, CXProviderDelegate>
@property (nonatomic, strong) TVOCall *call;
@property (nonatomic, strong) PKPushRegistry *voipRegistry;
@property (nonatomic, strong) TVOCallInvite *callInvite;
@property (nonatomic, strong) CXProvider *callKitProvider;
@property (nonatomic, strong) CXCallController *callKitCallController;
@property (nonatomic, strong) void(^incomingPushCompletionCallback)(void);
@property (nonatomic, strong) void(^callKitCompletionCallback)(BOOL);
@end

@implementation TwilioVoiceModule {
    NSString* _accessToken;
    NSMutableString* _deviceToken;
    PKPushCredentials* _cachedPushCredential;
    bool _hasListeners;
    NSTimer *TimeOfAccept;
    NSTimer *TimeOfReject;
    NSUUID *callKitUUID;
    int acceptTimerCount;
    int rejectTimerCount;
    NSMutableDictionary *acceptTimerParams;
    NSMutableDictionary *rejectTimerParams;
    NSMutableDictionary *callIncomingParams;
}

RCT_EXPORT_MODULE()

-(NSArray<NSString *> *)supportedEvents
{
    return @[@"callAccepted", @"callRejected", @"deviceRegistered", @"deviceNotRegistered", @"connectionDidConnect", @"connectionDidDisconnect", @"connectionDidFailed", @"connectionDidRinging", @"connectionDidReconnecting", @"connectionDidReconnect", @"callIncoming", @"callIncomingCancelled"];
}

// Will be called when this module's first listener is added.
-(void)startObserving {
    _hasListeners = YES;
}
+ (id)allocWithZone:(NSZone *)zone {
    static TwilioVoiceModule *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [super allocWithZone:zone];
    });
    return sharedInstance;
}

- (void)configureCallKit {
    CXProviderConfiguration *configuration = [[CXProviderConfiguration alloc] initWithLocalizedName:@"Anyone"];
    configuration.maximumCallGroups = 1;
    configuration.maximumCallsPerCallGroup = 1;
    UIImage *callkitIcon = [UIImage imageNamed:@"appIcon"];
    configuration.iconTemplateImageData = UIImagePNGRepresentation(callkitIcon);
    configuration.ringtoneSound = @"call_incoming_law.wav";

    _callKitProvider = [[CXProvider alloc] initWithConfiguration:configuration];
    [_callKitProvider setDelegate:self queue:nil];

    _callKitCallController = [[CXCallController alloc] init];
}

// Will be called when this module's last listener is removed, or on dealloc.
-(void)stopObserving {
    _hasListeners = NO;
}

-(void)sendEvent:(NSString*)eventName eventBody:(id)body
{
    if (_hasListeners) {
        [self sendEventWithName:eventName body:body];
    }
}
- (void)fetchAccessToken {
    NSString *kIdentity = [[NSUserDefaults standardUserDefaults] stringForKey:@"kIdentity"];
    NSString *accessTokenEndpointWithIdentity = [NSString stringWithFormat:@"%@?identity=%@", kAccessTokenEndpoint, [kIdentity length] == 0 ? @"testidentity" : kIdentity];
    NSString *accessTokenURLString = [kYourServerBaseURLString stringByAppendingString:accessTokenEndpointWithIdentity];

    NSString *accessToken = [NSString stringWithContentsOfURL:[NSURL URLWithString:accessTokenURLString]
                                                     encoding:NSUTF8StringEncoding
                                                        error:nil];
    [self configureCallKit];
    self->_accessToken = accessToken;
    if (![self checkRecordPermission]) {
        [self requestRecordPermission:^(BOOL granted) {
            if (granted) {
            }
        }];
    }
}

//- (void)dealloc {
//    if (self.callKitProvider) {
//        [self.callKitProvider invalidate];
//    }
//}

RCT_EXPORT_METHOD(initWithToken:(NSString *)token withId:(NSString *)_userIdentity resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
{
    if ([token isEqualToString:@""]) {
        reject(@"400", @"Invalid token detected", nil);
        return;
    }
    [[NSUserDefaults standardUserDefaults] setObject:_userIdentity forKey:@"kIdentity"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    if (![self checkRecordPermission]) {
        [self requestRecordPermission:^(BOOL granted) {
            if (!granted) {
                reject(@"400", @"Record permission is required to be initialized", nil);
            } else {
                [self credentialsUpdated:self->_cachedPushCredential];
                resolve(@{@"initialized": @true});
            }
        }];
    } else {
        [self credentialsUpdated:_cachedPushCredential];
        resolve(@{@"initialized": @true});
    }
}

RCT_EXPORT_METHOD(connect:(NSDictionary *)params)
{
    if (!_accessToken) {
        return;
    }
    if (self.call && self.call.state == TVOCallStateConnected) {
        [self.call disconnect];
    } else {
        TVOConnectOptions *connectOptions = [TVOConnectOptions optionsWithAccessToken:_accessToken block:^(TVOConnectOptionsBuilder * _Nonnull builder) {
            builder.params = params;
//            builder.uuid = [NSUUID UUID];
        }];
        self.call = [TwilioVoice connectWithOptions:connectOptions delegate:self];
    }
}

RCT_EXPORT_METHOD(disconnect)
{
    if (self.call) {
        [self.call disconnect];
    }
}

RCT_EXPORT_METHOD(setMuted:(BOOL)isMuted)
{
    if (self.call) {
        self.call.muted = isMuted;
    }
}

RCT_EXPORT_METHOD(setSpeakerPhone:(BOOL)isSpeaker)
{
    NSError *error = nil;
    if (isSpeaker) {
        if (![[AVAudioSession sharedInstance] overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker
                                                                error:&error]) {
            NSLog(@"Turn on speaker error: %@", [error localizedDescription]);
        }
    } else {
        if (![[AVAudioSession sharedInstance] overrideOutputAudioPort:AVAudioSessionPortOverrideNone
                                                                error:&error]) {
            NSLog(@"Turn off speaker error: %@", [error localizedDescription]);
        }
    }
}

RCT_EXPORT_METHOD(sendDigits:(NSString *)digits)
{
    if (self.call) {
        [self.call sendDigits:digits];
    }
}

RCT_EXPORT_METHOD(getVersion:(RCTResponseSenderBlock)callback)
{
    NSString *version = [TwilioVoice sdkVersion];
    callback(@[version]);
}

RCT_EXPORT_METHOD(getActiveCall:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
{
    if (self.call) {
       resolve([self paramsForCall:self.call]);
    } else {
        reject(@"400", @"There is no active call", nil);
    }
}

RCT_EXPORT_METHOD(accept)
{
    if (self.callInvite) {
        self.call = [self.callInvite acceptWithDelegate:self];
    }
}

RCT_EXPORT_METHOD(reject)
{
    if (self.callInvite) {
        [self.callInvite reject];
    }
}

- (BOOL)checkRecordPermission
{
    AVAudioSessionRecordPermission permissionStatus = [[AVAudioSession sharedInstance] recordPermission];
    return permissionStatus == AVAudioSessionRecordPermissionGranted;
}

- (void)requestRecordPermission:(void(^)(BOOL))completion
{
    [[AVAudioSession sharedInstance] requestRecordPermission:^(BOOL granted) {
        completion(granted);
    }];
}

- (NSMutableDictionary *)paramsForCall:(TVOCall *)call
{
    NSMutableDictionary *callParams = [[NSMutableDictionary alloc] init];
    if (call == nil) {
        return callParams;
    }
    [callParams setObject:call.sid forKey:@"call_sid"];
    if (call.state == TVOCallStateConnecting) {
        [callParams setObject:StateConnecting forKey:@"call_state"];
    } else if (call.state == TVOCallStateConnected) {
        [callParams setObject:StateConnected forKey:@"call_state"];
    } else if (call.state == TVOCallStateRinging) {
        [callParams setObject:StateRinging forKey:@"call_state"];
    } else if (call.state == TVOCallStateReconnecting) {
        [callParams setObject:StateReconnecting forKey:@"call_state"];
    } else if (call.state == TVOCallStateDisconnected) {
        [callParams setObject:StateDisconnected forKey:@"call_state"];
    }

    if (call.from) {
        [callParams setObject:call.from forKey:@"call_from"];
    }
    if (call.to) {
        [callParams setObject:call.to forKey:@"call_to"];
    }

    return callParams;
}


- (NSMutableDictionary *)paramsForError:(NSError *)error {
    NSMutableDictionary *params = [self paramsForCall:self.call];

    if (error) {
        NSMutableDictionary *errorParams = [[NSMutableDictionary alloc] init];
        if (error.code) {
            [errorParams setObject:[@([error code]) stringValue] forKey:@"code"];
        }
        if (error.domain) {
            [errorParams setObject:[error domain] forKey:@"domain"];
        }
        if (error.localizedDescription) {
            [errorParams setObject:[error localizedDescription] forKey:@"message"];
        }
        if (error.localizedFailureReason) {
            [errorParams setObject:[error localizedFailureReason] forKey:@"reason"];
        }
        [params setObject:errorParams forKey:@"error"];
    }
    return params;
}

#pragma mark - TVOCallDelegate methods
- (void)call:(nonnull TVOCall *)call didDisconnectWithError:(nullable NSError *)error
{
    [UIDevice currentDevice].proximityMonitoringEnabled = NO;
    NSMutableDictionary *params = [self paramsForError:error];
    NSLog(@"An error occurred while connectionDidDisconnect: %@", error);
    [self sendEvent:@"connectionDidDisconnect" eventBody:params];

    if (@available(iOS 10.0, *) && self->callKitUUID) {
        dispatch_time_t delay = dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC * 1);
        dispatch_after(delay, dispatch_get_main_queue(), ^(void){
            CXEndCallAction *endCallAction = [[CXEndCallAction alloc] initWithCallUUID:self->callKitUUID];
            CXTransaction *transaction = [[CXTransaction alloc] initWithAction:endCallAction];

            [self.callKitCallController requestTransaction:transaction completion:^(NSError *error) {
                self->callKitUUID = nil;
            }];
        });
    }
    if (self->_call && self->_call.sid == call.sid) {
        self->_call = nil;
    }
}

- (void)call:(nonnull TVOCall *)call didFailToConnectWithError:(nonnull NSError *)error
{
    [UIDevice currentDevice].proximityMonitoringEnabled = NO;
    NSMutableDictionary *params = [self paramsForError:error];
    [self sendEvent:@"connectionDidFailed" eventBody:params];
    if (@available(iOS 10.0, *) && self->callKitUUID) {
        dispatch_time_t delay = dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC * 1);
        dispatch_after(delay, dispatch_get_main_queue(), ^(void){
            CXEndCallAction *endCallAction = [[CXEndCallAction alloc] initWithCallUUID:self->callKitUUID];
            CXTransaction *transaction = [[CXTransaction alloc] initWithAction:endCallAction];

            [self.callKitCallController requestTransaction:transaction completion:^(NSError *error) {
                self->callKitUUID = nil;
            }];
        });
    }
    if (self->_call && self->_call.sid == call.sid) {
        self->_call = nil;
    }
}

- (void)callDidConnect:(nonnull TVOCall *)call
{
    self->_call = call;
    [UIDevice currentDevice].proximityMonitoringEnabled = YES;
    NSMutableDictionary *paramsForCall = [self paramsForCall:call];
    [self sendEvent:@"connectionDidConnect" eventBody:paramsForCall];
}

- (void)callDidStartRinging:(nonnull TVOCall *)call
{
    self->_call = call;

    NSMutableDictionary *paramsForCall = [self paramsForCall:call];
    [self sendEvent:@"connectionDidRinging" eventBody:paramsForCall];
}

- (void)call:(nonnull TVOCall *)call isReconnectingWithError:(nonnull NSError *)error
{
    self->_call = call;
    NSMutableDictionary *paramsForCall = [self paramsForError:error];
    [self sendEvent:@"connectionDidReconnecting" eventBody:paramsForCall];
}

- (void)callDidReconnect:(nonnull TVOCall *)call
{
    [UIDevice currentDevice].proximityMonitoringEnabled = YES;
    self->_call = call;
    NSMutableDictionary *paramsForCall = [self paramsForCall:call];
    [self sendEvent:@"connectionDidReconnect" eventBody:paramsForCall];
}


- (void)callInviteReceived:(nonnull TVOCallInvite *)callInvite {
    UIApplicationState state = [[UIApplication sharedApplication] applicationState];
    if (state == UIApplicationStateBackground || state == UIApplicationStateInactive) {
        if (@available(iOS 10.0, *)) {
            CXCallUpdate *callUpdate = [[CXCallUpdate alloc] init];
            NSDictionary<NSString *, NSString *> *clientParams = callInvite.customParameters;
            NSString *fromName = [clientParams valueForKey:@"fromName"];
            NSString *topicTitle = [clientParams valueForKey:@"topicTitle"];
            NSString *handle = [NSString stringWithFormat:@"%@ is calling about %@", fromName, topicTitle];
            NSUUID *uuid = [NSUUID UUID];
            if (handle == nil || uuid == nil) {
                return;
            }
            CXHandle *callHandle = [[CXHandle alloc] initWithType:CXHandleTypeGeneric value:handle];
            callUpdate.remoteHandle = callHandle;
            callUpdate.supportsDTMF = YES;
            callUpdate.supportsHolding = NO;
            callUpdate.supportsGrouping = NO;
            callUpdate.supportsUngrouping = NO;
            callUpdate.hasVideo = NO;

            [self.callKitProvider reportNewIncomingCallWithUUID:uuid update:callUpdate completion:^(NSError *error) {
                if (error) {

                } else {
                    self->_callInvite = callInvite;
                    NSMutableDictionary * params = [[NSMutableDictionary alloc] init];
                    [params setObject:callInvite.callSid forKey:@"call_sid"];
                    [params setObject:callInvite.from forKey:@"call_from"];
                    [params setObject:callInvite.to forKey:@"call_to"];
                    NSDictionary<NSString *, NSString *> *customParams = callInvite.customParameters;
                    NSArray<NSString *> *allKeys = [customParams allKeys];
                    [allKeys enumerateObjectsUsingBlock:^(NSString * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                        [params setObject:[customParams objectForKey:obj] forKey:obj];
                    }];
                    if (!self->_hasListeners) {
                        self->callIncomingParams = params;
                    }
                    [self sendEvent:@"callIncoming" eventBody:params];
                }
            }];
        }
    } else if (state == UIApplicationStateActive) {

        self->_callInvite = callInvite;
        NSMutableDictionary * params = [[NSMutableDictionary alloc] init];
        [params setObject:callInvite.callSid forKey:@"call_sid"];
        [params setObject:callInvite.from forKey:@"call_from"];
        [params setObject:callInvite.to forKey:@"call_to"];
        NSDictionary<NSString *, NSString *> *customParams = callInvite.customParameters;
        NSArray<NSString *> *allKeys = [customParams allKeys];
        [allKeys enumerateObjectsUsingBlock:^(NSString * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            [params setObject:[customParams objectForKey:obj] forKey:obj];
        }];
        if (!self->_hasListeners) {
            self->callIncomingParams = params;
        }
        [self sendEvent:@"callIncoming" eventBody:params];
    }
}

- (void)cancelledCallInviteReceived:(nonnull TVOCancelledCallInvite *)cancelledCallInvite {
    UIApplicationState state = [[UIApplication sharedApplication] applicationState];
    if (state == UIApplicationStateBackground || state == UIApplicationStateInactive) {
        if (@available(iOS 10.0, *)) {
            CXCallUpdate *callUpdate = [[CXCallUpdate alloc] init];
            NSString *handle = @"Anyone";
            NSUUID *uuid = [NSUUID UUID];
            if (handle == nil || uuid == nil) {
                return;
            }
            CXHandle *callHandle = [[CXHandle alloc] initWithType:CXHandleTypeGeneric value:handle];
            callUpdate.remoteHandle = callHandle;
            callUpdate.supportsDTMF = YES;
            callUpdate.supportsHolding = NO;
            callUpdate.supportsGrouping = NO;
            callUpdate.supportsUngrouping = NO;
            callUpdate.hasVideo = NO;

            [self.callKitProvider reportNewIncomingCallWithUUID:uuid update:callUpdate completion:^(NSError *error) {

                if (self->_callInvite && self->_callInvite.callSid == cancelledCallInvite.callSid) {
                    self->_callInvite = nil;
                    NSMutableDictionary * params = [[NSMutableDictionary alloc] init];
                    [params setObject:cancelledCallInvite.callSid forKey:@"call_sid"];
                    [params setObject:cancelledCallInvite.from forKey:@"call_from"];
                    [params setObject:cancelledCallInvite.to forKey:@"call_to"];
                    [self sendEvent:@"callIncomingCancelled" eventBody:params];
                }
            }];
        }
    } else if (state == UIApplicationStateActive) {

        if (self->_callInvite && self->_callInvite.callSid == cancelledCallInvite.callSid) {
            self->_callInvite = nil;
            NSMutableDictionary * params = [[NSMutableDictionary alloc] init];
            [params setObject:cancelledCallInvite.callSid forKey:@"call_sid"];
            [params setObject:cancelledCallInvite.from forKey:@"call_from"];
            [params setObject:cancelledCallInvite.to forKey:@"call_to"];
            [self sendEvent:@"callIncomingCancelled" eventBody:params];
        }
    }
}

- (NSString *)fetchAccessTokenFromIdentity {
    NSString *kIdentity = [[NSUserDefaults standardUserDefaults] stringForKey:@"kIdentity"];
    NSString *accessTokenEndpointWithIdentity = [NSString stringWithFormat:@"%@?identity=%@", kAccessTokenEndpoint, [kIdentity length] == 0 ? @"testidentity" : kIdentity];
    NSString *accessTokenURLString = [kYourServerBaseURLString stringByAppendingString:accessTokenEndpointWithIdentity];

    NSString *accessToken = [NSString stringWithContentsOfURL:[NSURL URLWithString:accessTokenURLString]
                                                     encoding:NSUTF8StringEncoding
                                                        error:nil];
    self->_accessToken = accessToken;
    return accessToken;
}

#pragma mark - PushKitEventDelegate
- (void)credentialsUpdated:(PKPushCredentials *)credentials {
    NSString *accessToken = [self fetchAccessTokenFromIdentity];
    _cachedPushCredential = credentials;
    NSData *cachedDeviceToken = [[NSUserDefaults standardUserDefaults] objectForKey:kCachedDeviceToken];
    if (![cachedDeviceToken isEqualToData:credentials.token] || [accessToken isEqualToString:_accessToken]) {
        cachedDeviceToken = credentials.token;
        /*
         * Perform registration if a new device token is detected.
         */
        [TwilioVoice registerWithAccessToken:accessToken
                             deviceTokenData:cachedDeviceToken
                                  completion:^(NSError *error) {
             if (error) {
                 NSLog(@"An error occurred while registering: %@", [error localizedDescription]);
             } else {
                 NSLog(@"Successfully registered for VoIP push notifications.");

                 /*
                  * Save the device token after successfully registered.
                  */
                 [[NSUserDefaults standardUserDefaults] setObject:cachedDeviceToken forKey:kCachedDeviceToken];
                 self->_accessToken = accessToken;
             }
         }];
    }
}

- (void)credentialsInvalidated {
    NSString *accessToken = [self fetchAccessTokenFromIdentity];

    NSData *cachedDeviceToken = [[NSUserDefaults standardUserDefaults] objectForKey:kCachedDeviceToken];
    if ([cachedDeviceToken length] > 0) {
        [TwilioVoice unregisterWithAccessToken:accessToken
                               deviceTokenData:cachedDeviceToken
                                    completion:^(NSError *error) {
            if (error) {
                NSLog(@"An error occurred while unregistering: %@", [error localizedDescription]);
            } else {
                NSLog(@"Successfully unregistered for VoIP push notifications.");
            }
        }];
    }

    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kCachedDeviceToken];
}

- (void)incomingPushReceived:(PKPushPayload *)payload withCompletionHandler:(void (^)(void))completion {
    // The Voice SDK will use main queue to invoke `cancelledCallInviteReceived:error` when delegate queue is not passed
    if (![TwilioVoice handleNotification:payload.dictionaryPayload delegate:self delegateQueue:nil]) {
        NSLog(@"This is not a valid Twilio Voice notification.");
    }

    if (completion) {
        if ([[NSProcessInfo processInfo] operatingSystemVersion].majorVersion < 13) {
            // Save for later when the notification is properly handled.
            self.incomingPushCompletionCallback = completion;
        } else {
            /*
             * The Voice SDK processes the call notification and returns the call invite synchronously.
             * Report the incoming call to CallKit and fulfill the completion before exiting this callback method.
             */
            completion();
        }
    }
}

- (void)incomingPushHandled {
    if (self.incomingPushCompletionCallback) {
        self.incomingPushCompletionCallback();
        self.incomingPushCompletionCallback = nil;
    }
}

#pragma mark - CXProviderDelegate

- (void)providerDidReset:(CXProvider *)provider {
    NSLog(@"providerDidReset:");
}

- (void)providerDidBegin:(CXProvider *)provider {
    NSLog(@"providerDidBegin:");
}

- (void)provider:(CXProvider *)provider didActivateAudioSession:(AVAudioSession *)audioSession {
    NSLog(@"provider:didActivateAudioSession:");
}

- (void)provider:(CXProvider *)provider didDeactivateAudioSession:(AVAudioSession *)audioSession {
    NSLog(@"provider:didDeactivateAudioSession:");
}

- (void)provider:(CXProvider *)provider timedOutPerformingAction:(CXAction *)action {
    NSLog(@"provider:timedOutPerformingAction:");
}

- (void)provider:(CXProvider *)provider performStartCallAction:(CXStartCallAction *)action {
    NSLog(@"provider:performStartCallAction:");
}

- (void)provider:(CXProvider *)provider performAnswerCallAction:(CXAnswerCallAction *)action {
    NSLog(@"provider:performAnswerCallAction:");

    NSMutableDictionary * params = [[NSMutableDictionary alloc] init];

    if (self.callInvite) {
        NSLog(@"provider:performAnswerCallAction:self.callInvite");
        [params setObject:self.callInvite.callSid forKey:@"call_sid"];
        [params setObject:self.callInvite.from forKey:@"call_from"];
        [params setObject:self.callInvite.to forKey:@"call_to"];
        self.call = [self.callInvite acceptWithDelegate:self];
        if (self->_hasListeners) {
            if (self->callIncomingParams) {
                [self sendEvent:@"callIncoming" eventBody:self->callIncomingParams];
                self->callIncomingParams = nil;
            }
            [self sendEvent:@"callAccepted" eventBody:params];
        } else {
            self->acceptTimerParams = params;
            self->acceptTimerCount = 0;
            self->TimeOfAccept = [NSTimer scheduledTimerWithTimeInterval:1.0  target:self selector:@selector(acceptTimerAction) userInfo:nil repeats:YES];
        }
        self->_callInvite = nil;
    }
    if (@available(iOS 10.0, *)) {
        self->callKitUUID = action.callUUID;
    }
    [action fulfill];
}

- (void)provider:(CXProvider *)provider performEndCallAction:(CXEndCallAction *)action {
    NSLog(@"provider:performEndCallAction:");

    NSMutableDictionary * params = [[NSMutableDictionary alloc] init];

    if (self.callInvite) {
        NSLog(@"provider:performEndCallAction:self.callInvite");
        [params setObject:self.callInvite.callSid forKey:@"call_sid"];
        [params setObject:self.callInvite.from forKey:@"call_from"];
        [params setObject:self.callInvite.to forKey:@"call_to"];
        [self.callInvite reject];
        if (self->_hasListeners) {
            if (self->callIncomingParams) {
                [self sendEvent:@"callIncoming" eventBody:self->callIncomingParams];
                self->callIncomingParams = nil;
            }
            [self sendEvent:@"callRejected" eventBody:params];
        } else {
            self->rejectTimerParams = params;
            self->rejectTimerCount = 0;
            self->TimeOfReject = [NSTimer scheduledTimerWithTimeInterval:1.0  target:self selector:@selector(rejectTimerAction) userInfo:nil repeats:YES];
        }
        self->_callInvite = nil;
    }

    [action fulfill];
}

-(void)acceptTimerAction
{
    if (self->_hasListeners) {
        if (self->callIncomingParams) {
            [self sendEvent:@"callIncoming" eventBody:self->callIncomingParams];
            self->callIncomingParams = nil;
        }
        [self sendEvent:@"callAccepted" eventBody:self->acceptTimerParams];
        [self->TimeOfAccept invalidate];
        self->TimeOfAccept = nil;
    } else {
        if (self->acceptTimerCount > 20) {
            [self->TimeOfAccept invalidate];
            self->TimeOfAccept = nil;
        } else {
            self->acceptTimerCount += 1;
        }
    }
}

-(void)rejectTimerAction
{
    if (self->_hasListeners) {
        if (self->callIncomingParams) {
            [self sendEvent:@"callIncoming" eventBody:self->callIncomingParams];
            self->callIncomingParams = nil;
        }
        [self sendEvent:@"callRejected" eventBody:self->rejectTimerParams];
        [self->TimeOfReject invalidate];
        self->TimeOfReject = nil;
    } else {
        if (self->rejectTimerCount > 20) {
            [self->TimeOfReject invalidate];
            self->TimeOfReject = nil;
        } else {
            self->rejectTimerCount += 1;
        }
    }
}

@end
