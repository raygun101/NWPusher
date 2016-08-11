//
//  NWAppDelegate.m
//  Pusher
//
//  Copyright (c) 2013 noodlewerk. All rights reserved.
//

#import "NWAppDelegate.h"
#import "NWHub.h"
#import "NWPusher.h"
#import "NWNotification.h"
#import "NWLCore.h"
#import "NWSSLConnection.h"
#import "NWSecTools.h"

// TODO: Export your push certificate and key in PKCS12 format to pusher.p12 in the root of the project directory.
static NSString * const pkcs12FileName = @"iphone-push-fnb-enterprise-new.p12";

// TODO: Set the password of this .p12 file below, but be careful *not* to commit passwords to a (public) repository.
static NSString * const pkcs12Password = @"changeit";

// TODO: Set the device token of the device you want to push to, see
//       `-application:didRegisterForRemoteNotificationsWithDeviceToken:` for more details.
static NWPusherViewController *controller = nil;

@interface NWPusherViewController () <NWHubDelegate> @end

@implementation NWPusherViewController {
    UIButton *_connectButton;
    UITextView *_textField;
    UIButton *_pushButton;
    UILabel *_infoLabel;
    UITextField *_idField;
    NWHub *_hub;
    NSUInteger _index;
    dispatch_queue_t _serial;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    controller = self;
    NWLAddPrinter("NWPusher", NWPusherPrinter, 0);
    NWLPrintInfo();
    _serial = dispatch_queue_create("NWAppDelegate", DISPATCH_QUEUE_SERIAL);
    
    _connectButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    _connectButton.frame = CGRectMake(20, 20, self.view.bounds.size.width / 2 - 40, 40);
    [_connectButton setTitle:@"Connect" forState:UIControlStateNormal];
    [_connectButton addTarget:self action:@selector(connect) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_connectButton];
    
    _idField = [[UITextField alloc] init];
    _idField.frame = CGRectMake(10, 70, self.view.bounds.size.width - 20, 20);
    _idField.font = [_idField.font fontWithSize: 8];
    _idField.text = @"f9d7fe14ef237197e69e85584b30f4ae06acbabdd67653368197cf5768127c01";
    [self.view addSubview:_idField];
    
    _textField = [[UITextView alloc] init];
    _textField.frame = CGRectMake(20, 100, self.view.bounds.size.width - 40, self.view.bounds.size.height - 90);
    _textField.text = @"Testing..";
    [self.view addSubview:_textField];
    
    _pushButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    _pushButton.frame = CGRectMake(self.view.bounds.size.width / 2 + 20, 20, self.view.bounds.size.width / 2 - 40, 40);
    [_pushButton setTitle:@"Push" forState:UIControlStateNormal];
    [_pushButton addTarget:self action:@selector(push) forControlEvents:UIControlEventTouchUpInside];
    _pushButton.enabled = NO;
    [self.view addSubview:_pushButton];
    
    _infoLabel = [[UILabel alloc] init];
    _infoLabel.frame = CGRectMake(20, self.view.bounds.size.height - 30, self.view.bounds.size.width - 40, 26);
    _infoLabel.font = [UIFont systemFontOfSize:12];
    [self.view addSubview:_infoLabel];
    
    NWLogInfo(@"Connect with Apple's Push Notification service");
    
    _textField.text = [NSString stringWithContentsOfFile: [[NSBundle mainBundle] pathForResource: @"Payload" ofType:@"json"] encoding: NSUTF8StringEncoding error: nil];
}

- (void)connect
{
    if (!_hub) {
        NWLogInfo(@"Connecting..");
        _connectButton.enabled = NO;
        dispatch_async(_serial, ^{
            NSURL *url = [NSBundle.mainBundle URLForResource:pkcs12FileName withExtension:nil];
            NSData *pkcs12 = [NSData dataWithContentsOfURL:url];
            NSError *error = nil;
            NWHub *hub = [NWHub connectWithDelegate:self PKCS12Data:pkcs12 password:pkcs12Password error:&error];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (hub) {
                    NSError *error = nil;
                    NWCertificateRef certificate = [NWSecTools certificateWithIdentity:hub.pusher.connection.identity error:&error];
                    NWError(error);
                    BOOL sandbox = [NWSecTools isSandboxCertificate:certificate];
                    NSString *summary = [NWSecTools summaryWithCertificate:certificate];
                    NWLogInfo(@"Connected to APN: %@%@", summary, sandbox ? @" (sandbox)" : @"");
                    _hub = hub;
                    _pushButton.enabled = YES;
                    [_connectButton setTitle:@"Disconnect" forState:UIControlStateNormal];
                } else {
                    NWLogWarn(@"Unable to connect: %@", error.localizedDescription);
                }
                _connectButton.enabled = YES;
            });
        });
    } else {
        _pushButton.enabled = NO;
        [_hub disconnect]; _hub = nil;
        NWLogInfo(@"Disconnected");
        [_connectButton setTitle:@"Connect" forState:UIControlStateNormal];
    }
}

- (void)push
{
    NSString *payload = _textField.text;
    NSString *token = _idField.text;
    NWLogInfo(@"Pushing..");
    
    dispatch_async(_serial, ^{
        NSUInteger failed = [_hub pushPayload:payload token:token];
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC));
        dispatch_after(popTime, _serial, ^(void){
            NSUInteger failed2 = failed + [_hub readFailed];
            if (!failed2) NWLogInfo(@"Payload has been pushed");
        });
    });
}

- (void)notification:(NWNotification *)notification didFailWithError:(NSError *)error
{
    dispatch_async(dispatch_get_main_queue(), ^{
        //NSLog(@"failed notification: %@ %@ %lu %lu %lu", notification.payload, notification.token, notification.identifier, notification.expires, notification.priority);
        NWLogWarn(@"Notification error: %@", error.localizedDescription);
    });
}


#pragma mark - NWLogging

- (void)log:(NSString *)message warning:(BOOL)warning
{
    dispatch_async(dispatch_get_main_queue(), ^{
        _infoLabel.textColor = warning ? UIColor.redColor : UIColor.blackColor;
        _infoLabel.text = message;
    });
}

static void NWPusherPrinter(NWLContext context, CFStringRef message, void *info) {
    BOOL warning = strncmp(context.tag, "warn", 5) == 0;
    [controller log:(__bridge NSString *)message warning:warning];
}

@end


@implementation NWAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    NWPusherViewController *controller = [[NWPusherViewController alloc] init];
    self.window.rootViewController = controller;
    self.window.backgroundColor = [UIColor whiteColor];
    [self.window makeKeyAndVisible];
    return YES;
}

@end
