//
//  PBJVideoPlayerController.h
//
//  Created by Patrick Piemonte on 5/27/13.
//  Copyright (c) 2013-present, Patrick Piemonte, http://patrickpiemonte.com
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy of
//  this software and associated documentation files (the "Software"), to deal in
//  the Software without restriction, including without limitation the rights to
//  use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
//  the Software, and to permit persons to whom the Software is furnished to do so,
//  subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
//  FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
//  COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
//  IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
//  CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
//

#import <UIKit/UIKit.h>
#import "PBJVideoView.h"
@import CoreMedia;

typedef NS_ENUM(NSInteger, PBJVideoPlayerPlaybackState)
{
    PBJVideoPlayerPlaybackStateStopped = 0,
    PBJVideoPlayerPlaybackStatePlaying,
    PBJVideoPlayerPlaybackStatePaused,
    PBJVideoPlayerPlaybackStateFailed,
};

typedef NS_ENUM(NSInteger, PBJVideoPlayerBufferingState)
{
    PBJVideoPlayerBufferingStateUnknown = 0,
    PBJVideoPlayerBufferingStateReady,
    PBJVideoPlayerBufferingStateDelayed,
};

FOUNDATION_EXTERN NSString * const PBJVideoPlayerStartPlayNotification;
FOUNDATION_EXTERN NSString * const PBJVideoPlayerDidPauseNotification;
FOUNDATION_EXTERN NSString * const PBJVideoPlayerDidStopNotification;

// PBJVideoPlayerController.view provides the interface for playing/streaming videos
@class AVAsset;

@interface PBJVideoPlayer : NSObject

// if you want to set the AVAsset manually, you can do so here
@property (nonatomic) AVAsset *asset;

// if you'd rather specify a path to your video than create an AVAsset, set videoPath
@property (nonatomic, strong) NSURL *videoURL;

@property (nonatomic, copy) NSString *videoFillMode; // default, AVLayerVideoGravityResizeAspect

// Settings
@property (nonatomic) BOOL playbackLoops;
@property (nonatomic) BOOL playbackFreezesAtEnd;
@property (nonatomic) BOOL preloadAssetBeforePlaying;

@property (nonatomic, readonly) PBJVideoPlayerPlaybackState playbackState;
@property (nonatomic, readonly) PBJVideoPlayerBufferingState bufferingState;

@property (nonatomic, readonly) NSTimeInterval maxDuration;
// set to YES to mute audio
@property (nonatomic) BOOL muted;

// set the number of times to try reloading the video
@property (nonatomic) unsigned int retries;

- (void)playFromBeginning;
- (void)playFromCurrentTime;
- (void)seekToTime:(CMTime)time;
- (void)pause;
- (void)stop;

@end

