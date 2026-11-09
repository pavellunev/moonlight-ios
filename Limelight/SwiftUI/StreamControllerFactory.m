//
//  StreamControllerFactory.m
//  Moonlight
//

#import "StreamControllerFactory.h"
#import "StreamFrameViewController.h"

@implementation StreamControllerFactory

+ (UIViewController*) makeStreamViewControllerWithConfig:(StreamConfiguration*)config {
    StreamFrameViewController* stream = [[StreamFrameViewController alloc] init];
    stream.streamConfig = config;
    return stream;
}

@end
