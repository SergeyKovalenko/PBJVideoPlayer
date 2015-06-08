//
//  PBJVideoPlayerController.m
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

#import <AVFoundation/AVFoundation.h>
#import "PBJVideoView.h"
#import "PBJVideoPlayer.h"
#import "PBJVideoPlayerController.h"

@interface PBJVideoPlayerController ()

@property (nonatomic, strong) PBJVideoView *videoView;
@property (nonatomic, readwrite) UITapGestureRecognizer *playbackGesture;
@end

@implementation PBJVideoPlayerController

@synthesize player = _player;

#pragma mark - view lifecycle

- (void)loadView
{
    CGRect frame = [[UIScreen mainScreen] applicationFrame];
    self.view = [[UIView alloc] initWithFrame:frame];
    self.videoView = [[PBJVideoView alloc] initWithFrame:frame];
    self.videoView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:self.videoView];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self setupVideoView];
    [self addPlaybackGesture];
}

- (void)addPlaybackGesture
{
    self.playbackGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_handleTap:)];
    [self.view addGestureRecognizer:self.playbackGesture];
}

- (void)setupVideoView
{
    // load the playerLayer view
    self.videoView.videoFillMode = AVLayerVideoGravityResizeAspect;
    self.videoView.player = self.player;
}

- (PBJVideoPlayer *)player
{
    if (!_player)
    {
        _player = [[PBJVideoPlayer alloc] init];
    }
    return _player;
}

- (void)setPlayer:(PBJVideoPlayer *)player
{
    if (_player != player)
    {
        _player = player;
        if ([self isViewLoaded])
        {
            [self setupVideoView];
        }
    }
}

- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];

    if (self.player.playbackState == PBJVideoPlayerPlaybackStatePlaying)
    {
        [self.player pause];
    }
}

#pragma mark - UIGestureRecognizer Action

- (void)_handleTap:(UIGestureRecognizer *)gestureRecognizer
{
    switch (self.player.playbackState)
    {
        case PBJVideoPlayerPlaybackStateStopped:
        {
            [self.player playFromBeginning];
            break;
        }
        case PBJVideoPlayerPlaybackStatePaused:
        {
            [self.player playFromCurrentTime];
            break;
        }
        case PBJVideoPlayerPlaybackStatePlaying:
        case PBJVideoPlayerPlaybackStateFailed:
        default:
        {
            [self.player pause];
            break;
        }
    }
}

@end
