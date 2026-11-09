//
//  StreamControllerFactory.h
//  Moonlight
//
//  StreamFrameViewController.h can't be imported by the bridging header (its headers need the
//  generated Moonlight-Swift.h), so Swift creates the stream screen through this factory.
//

#import <UIKit/UIKit.h>

@class StreamConfiguration;

@interface StreamControllerFactory : NSObject

+ (UIViewController*) makeStreamViewControllerWithConfig:(StreamConfiguration*)config;

@end
