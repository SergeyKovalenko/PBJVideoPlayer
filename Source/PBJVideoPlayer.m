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

#import "PBJVideoPlayer.h"
#import <AVFoundation/AVFoundation.h>

#define LOG_PLAYER 0
#ifndef DLog
#if !defined(NDEBUG) && LOG_PLAYER
#   define DLog(fmt, ...) NSLog((@"player: " fmt), ##__VA_ARGS__);
#else
#   define DLog(...)
#endif
#endif

// KVO contexts
 void * PBJVideoPlayerObserverContext = &PBJVideoPlayerObserverContext;
 void * PBJVideoPlayerItemObserverContext = &PBJVideoPlayerItemObserverContext;
 void * PBJVideoPlayerLayerObserverContext = &PBJVideoPlayerLayerObserverContext;

NSString * const PBJVideoPlayerWillStartPlayingNotification = @"PBJVideoPlayerWillStartPlayingNotification";
NSString * const PBJVideoPlayerDidStartPlayingNotification = @"PBJVideoPlayerDidStartPlayingNotification";
NSString * const PBJVideoPlayerDidPauseNotification = @"PBJVideoPlayerDidPauseNotification";
NSString * const PBJVideoPlayerDidStopNotification = @"PBJVideoPlayerDidStopNotification";

// KVO player keys
static NSString *const PBJVideoPlayerControllerTracksKey = @"tracks";
static NSString *const PBJVideoPlayerControllerPlayableKey = @"playable";
static NSString *const PBJVideoPlayerControllerDurationKey = @"duration";
static NSString *const PBJVideoPlayerControllerRateKey = @"rate";

// KVO player item keys
static NSString *const PBJVideoPlayerControllerStatusKey = @"status";
static NSString *const PBJVideoPlayerControllerEmptyBufferKey = @"playbackBufferEmpty";
static NSString *const PBJVideoPlayerControllerPlayerKeepUpKey = @"playbackLikelyToKeepUp";

// KVO player layer keys
static NSString *const PBJVideoPlayerControllerReadyForDisplay = @"readyForDisplay";

// TODO: scrubbing support
//static float const PBJVideoPlayerControllerRates[PBJVideoPlayerRateCount] = { 0.25, 0.5, 0.75, 1, 1.5, 2 };
//static NSInteger const PBJVideoPlayerRateCount = 6;

@interface PBJVideoPlayer ()
{
    // flags
    struct
    {
        BOOL playbackLoops;
        BOOL playbackFreezesAtEnd;
    } __block _flags;
}

@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) AVPlayerItem *playerItem;
@property (nonatomic, strong) NSMutableArray *playerAccessors;
@property (nonatomic, readwrite) PBJVideoPlayerPlaybackState playbackState;
@property (nonatomic, readwrite) PBJVideoPlayerBufferingState bufferingState;
@end

@implementation PBJVideoPlayer

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        self.preloadAssetBeforePlaying = NO;

        self.player = [[AVPlayer alloc] init];
        self.playerAccessors = [NSMutableArray array];
        self.player.actionAtItemEnd = AVPlayerActionAtItemEndPause;

        // Player KVO
        [self.player addObserver:self forKeyPath:PBJVideoPlayerControllerRateKey options:(NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld) context:PBJVideoPlayerObserverContext];

        // Application NSNotifications
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc addObserver:self selector:@selector(_applicationWillResignActive:) name:UIApplicationWillResignActiveNotification object:nil];
        [nc addObserver:self selector:@selector(_applicationDidEnterBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
    }

    return self;
}

#pragma mark - getters/setters

- (BOOL)playbackLoops
{
    return _flags.playbackLoops;
}

- (void)setPlaybackLoops:(BOOL)playbackLoops
{
    _flags.playbackLoops = playbackLoops;
    if (!self.player)
    {
        return;
    }

    if (!_flags.playbackLoops)
    {
        self.player.actionAtItemEnd = AVPlayerActionAtItemEndPause;
    }
    else
    {
        self.player.actionAtItemEnd = AVPlayerActionAtItemEndNone;
    }
}

- (BOOL)playbackFreezesAtEnd
{
    return _flags.playbackFreezesAtEnd;
}

- (void)setPlaybackFreezesAtEnd:(BOOL)playbackFreezesAtEnd
{
    _flags.playbackFreezesAtEnd = playbackFreezesAtEnd;
}

- (NSTimeInterval)maxDuration
{
    NSTimeInterval maxDuration = -1;

    if (CMTIME_IS_NUMERIC(_playerItem.duration))
    {
        maxDuration = CMTimeGetSeconds(_playerItem.duration);
    }

    return maxDuration;
}

- (BOOL)muted
{
    return self.player.muted;
}

- (void)setMuted:(BOOL)muted
{
    DLog(@"muted: %u", muted);
    self.player.muted = muted;
}

- (void)setVideoURL:(NSURL *)videoURL
{
    if (_videoURL != videoURL)
    {
        if (_playbackState == PBJVideoPlayerPlaybackStatePlaying)
        {
            [self pause];
        }

        _bufferingState = PBJVideoPlayerBufferingStateUnknown;

        _videoURL = videoURL;

        if (self.preloadAssetBeforePlaying)
        {
            self.asset = [[AVURLAsset alloc] initWithURL:_videoURL options:nil];
        }
    }
}

- (void)setAsset:(AVAsset *)asset
{
    if (_asset == asset)
    {
        return;
    }

    if (_playbackState == PBJVideoPlayerPlaybackStatePlaying)
    {
        [self pause];
    }

    _bufferingState = PBJVideoPlayerBufferingStateUnknown;

    [self.playerAccessors removeAllObjects];

    _asset = asset;

    if (!_asset)
    {
        [self _setPlayerItem:nil];
    }
    if (self.preloadAssetBeforePlaying)
    {
        __weak typeof(self) weakSelf = self;
        [self preparePlayerItemWithBlock:^(AVPlayerItem *item, NSError *error) {
            if (item)
            {
                __strong typeof(weakSelf) strongSelf = weakSelf;
                // setup player
                [strongSelf _videoPlayerAudioSessionActive:NO]; // the next line causes the audio mode to change, so we need to update it here in addition to when we play
                [strongSelf _setPlayerItem:item];
            }
        }];
    }
}

- (void)preparePlayerItemWithBlock:(void (^)(AVPlayerItem *, NSError *error))block
{
    if (block)
    {
        NSArray *keys = @[PBJVideoPlayerControllerTracksKey,
                          PBJVideoPlayerControllerPlayableKey,
                          PBJVideoPlayerControllerDurationKey];
        __weak typeof(self) weakSelf = self;
        __weak AVAsset *weakAsset = _asset;
        [self.asset loadValuesAsynchronouslyForKeys:keys completionHandler:^{
            [self _enqueueBlockOnMainQueue:^{
                __strong typeof(weakSelf) strongSelf = weakSelf;
                __strong AVAsset *strongAsset = weakAsset;
                if (strongSelf.asset == strongAsset)
                {
                    // check the keys
                    for (NSString *key in keys)
                    {
                        NSError *error = nil;
                        AVKeyValueStatus keyStatus = [strongAsset statusOfValueForKey:key error:&error];
                        if (keyStatus == AVKeyValueStatusFailed)
                        {
                            DLog("asset load failed: %@", error);
                            strongSelf.playbackState = PBJVideoPlayerPlaybackStateFailed;
                            if (strongSelf.retries > 0)
                            {
                                strongSelf.retries--;
                                [strongSelf forceReload]; // force reload
                            }
                            else
                            {
                                block(nil, error);
                            }
                            return;
                        }
                    }

                    // check playable
                    if (!strongAsset.playable)
                    {
                        DLog("asset is not playable");
                        strongSelf.playbackState = PBJVideoPlayerPlaybackStateFailed;
                        if (strongSelf.retries > 0)
                        {
                            strongSelf.retries--;
                            [strongSelf forceReload]; // force reload
                        }
                        block(nil, nil);
                        return;
                    }

                    block([AVPlayerItem playerItemWithAsset:strongAsset], nil);
                }
            }];
        }];
    }
}

- (void)forceReload
{
    if (self.videoURL)
    {
        self.asset = [[AVURLAsset alloc] initWithURL:self.videoURL options:nil];
    }
    else if (self.asset)
    {
        AVURLAsset *URLAsset = [self.asset isKindOfClass:[AVURLAsset class]] ? (id) self.asset : nil;
        if (URLAsset)
        {
            self.asset = [[AVURLAsset alloc] initWithURL:URLAsset.URL options:nil];
        }
    }
    if (!self.preloadAssetBeforePlaying)
    {
        __weak typeof(self) weakSelf = self;
        [self preparePlayerItemWithBlock:^(AVPlayerItem *item, NSError *error) {
            if (item)
            {
                __strong typeof(weakSelf) strongSelf = weakSelf;
                // setup player
                [strongSelf _videoPlayerAudioSessionActive:NO]; // the next line causes the audio mode to change, so we need to update it here in addition to when we play
                [strongSelf _setPlayerItem:item];
            }
        }];
    }
}

- (void)_setPlayerItem:(AVPlayerItem *)playerItem
{
    if (_playerItem == playerItem)
    {
        return;
    }

    // remove observers
    if (_playerItem)
    {
        // AVPlayerItem KVO
        [_playerItem removeObserver:self forKeyPath:PBJVideoPlayerControllerEmptyBufferKey context:PBJVideoPlayerItemObserverContext];
        [_playerItem removeObserver:self forKeyPath:PBJVideoPlayerControllerPlayerKeepUpKey context:PBJVideoPlayerItemObserverContext];
        [_playerItem removeObserver:self forKeyPath:PBJVideoPlayerControllerStatusKey context:PBJVideoPlayerItemObserverContext];

        // notifications
        [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:_playerItem];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemFailedToPlayToEndTimeNotification object:_playerItem];
    }

    _playerItem = playerItem;

    // add observers
    if (_playerItem)
    {
        // AVPlayerItem KVO
        [_playerItem addObserver:self forKeyPath:PBJVideoPlayerControllerEmptyBufferKey options:(NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld) context:PBJVideoPlayerItemObserverContext];
        [_playerItem addObserver:self forKeyPath:PBJVideoPlayerControllerPlayerKeepUpKey options:(NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld) context:PBJVideoPlayerItemObserverContext];
        [_playerItem addObserver:self forKeyPath:PBJVideoPlayerControllerStatusKey options:(NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld) context:PBJVideoPlayerItemObserverContext];

        // notifications
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_playerItemDidPlayToEndTime:) name:AVPlayerItemDidPlayToEndTimeNotification object:_playerItem];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_playerItemFailedToPlayToEndTime:) name:AVPlayerItemFailedToPlayToEndTimeNotification object:_playerItem];
    }

    if (!_flags.playbackLoops)
    {
        self.player.actionAtItemEnd = AVPlayerActionAtItemEndPause;
    }
    else
    {
        self.player.actionAtItemEnd = AVPlayerActionAtItemEndNone;
    }

    [self.player replaceCurrentItemWithPlayerItem:_playerItem];
}

#pragma mark - init

- (void)dealloc
{
    // notifications
    [[NSNotificationCenter defaultCenter] removeObserver:self];

    // AVPlayer KVO
    [self.player removeObserver:self forKeyPath:PBJVideoPlayerControllerRateKey context:PBJVideoPlayerObserverContext];

    // player
    [self.player pause];

    // player item
    [self _setPlayerItem:nil];
}

#pragma mark - private methods

- (void)_videoPlayerAudioSessionActive:(BOOL)active
{
    NSString *category = (active && !self.muted) ? AVAudioSessionCategoryPlayback : AVAudioSessionCategoryAmbient;

    NSError *error = nil;
    [[AVAudioSession sharedInstance] setCategory:category error:&error];
    if (error)
    {
        DLog(@"audio session active error (%@)", error);
    }
}

- (void)accessPlayerWithBlock:(void (^)(AVPlayer *))accessBlock
{
    if (accessBlock)
    {
        if (!self.playerItem)
        {
            if (!self.asset && self.videoURL)
            {
                self.asset = [[AVURLAsset alloc] initWithURL:self.videoURL options:nil];
            }
            if (self.asset)
            {
                [self.playerAccessors addObject:accessBlock];

                __weak typeof(self) weakSelf = self;
                [self preparePlayerItemWithBlock:^(AVPlayerItem *item, NSError *error) {
                    if (item)
                    {
                        __strong typeof(weakSelf) strongSelf = weakSelf;
                        // setup player
                        [strongSelf _videoPlayerAudioSessionActive:NO]; // the next line causes the audio mode to change, so we need to update it here in addition to when we play
                        [strongSelf _setPlayerItem:item];
                        for ( void (^savedAccessBlock)(AVPlayer *) in strongSelf.playerAccessors)
                        {
                            savedAccessBlock(strongSelf.player);
                        }
                        [strongSelf.playerAccessors removeAllObjects];
                    }
                }];
            }
            else
            {
                accessBlock(nil);
            }
        }
        else
        {
            accessBlock(self.player);
        }
    }
}

#pragma mark - public methods

- (void)playFromBeginning
{
    DLog(@"playing from beginnging...");
    [[NSNotificationCenter defaultCenter] postNotificationName:PBJVideoPlayerWillStartPlayingNotification object:self userInfo:nil];
    __weak typeof(self) weakSelf = self;
    [self accessPlayerWithBlock:^(AVPlayer *player) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [player seekToTime:kCMTimeZero];
        strongSelf.playbackState = PBJVideoPlayerPlaybackStatePlaying;
        [strongSelf _videoPlayerAudioSessionActive:YES];
        [player play];
        if (strongSelf)
        {
            [[NSNotificationCenter defaultCenter] postNotificationName:PBJVideoPlayerDidStartPlayingNotification object:strongSelf userInfo:nil];
        }
    }];
}

- (void)playFromCurrentTime
{
    DLog(@"playing...");
    [[NSNotificationCenter defaultCenter] postNotificationName:PBJVideoPlayerWillStartPlayingNotification object:self userInfo:nil];
    __weak typeof(self) weakSelf = self;
    [self accessPlayerWithBlock:^(AVPlayer *player) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        strongSelf.playbackState = PBJVideoPlayerPlaybackStatePlaying;
        [strongSelf _videoPlayerAudioSessionActive:YES];
        [player play];
        if (strongSelf)
        {
            [[NSNotificationCenter defaultCenter] postNotificationName:PBJVideoPlayerDidStartPlayingNotification object:strongSelf userInfo:nil];
        }
    }];
}

- (void)seekToTime:(CMTime)time
{
    DLog(@"seekToTime...");
    [self accessPlayerWithBlock:^(AVPlayer *player) {
        [player seekToTime:time];
    }];
}

- (void)pause
{
    if (_playbackState != PBJVideoPlayerPlaybackStatePlaying)
    {
        return;
    }

    DLog(@"pause");

    __weak typeof(self) weakSelf = self;
    [self accessPlayerWithBlock:^(AVPlayer *player) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [player pause];
        strongSelf.playbackState = PBJVideoPlayerPlaybackStatePaused;
        [strongSelf _videoPlayerAudioSessionActive:NO];
        if (strongSelf)
        {
            [[NSNotificationCenter defaultCenter] postNotificationName:PBJVideoPlayerDidPauseNotification object:strongSelf userInfo:nil];
        }
    }];
}

- (void)stop
{
    if (_playbackState == PBJVideoPlayerPlaybackStateStopped)
    {
        return;
    }

    DLog(@"stop");

    __weak typeof(self) weakSelf = self;
    [self accessPlayerWithBlock:^(AVPlayer *player) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [player pause];
        strongSelf.playbackState = PBJVideoPlayerPlaybackStateStopped;
        [strongSelf _videoPlayerAudioSessionActive:NO];
        if (strongSelf)
        {
            [[NSNotificationCenter defaultCenter] postNotificationName:PBJVideoPlayerDidStopNotification object:strongSelf userInfo:nil];
        }
    }];
}

#pragma mark - main queue helper

typedef void (^PBJVideoPlayerBlock)();

- (void)_enqueueBlockOnMainQueue:(PBJVideoPlayerBlock)block
{
    dispatch_async(dispatch_get_main_queue(), ^{
        block();
    });
}

#pragma mark - AV Notifications

- (void)_playerItemDidPlayToEndTime:(NSNotification *)aNotification
{
    if (_flags.playbackLoops || !_flags.playbackFreezesAtEnd)
    {
        [self seekToTime:kCMTimeZero];
    }

    if (!_flags.playbackLoops)
    {
        [self stop];
    }
}

- (void)_playerItemFailedToPlayToEndTime:(NSNotification *)aNotification
{
    _playbackState = PBJVideoPlayerPlaybackStateFailed;
    DLog(@"video failed to play to end (%@)", [aNotification userInfo][AVPlayerItemFailedToPlayToEndTimeErrorKey]);
}

#pragma mark - App NSNotifications

- (void)_applicationWillResignActive:(NSNotification *)notification
{
    if (_playbackState == PBJVideoPlayerPlaybackStatePlaying)
    {
        [self pause];
    }
}

- (void)_applicationDidEnterBackground:(NSNotification *)notification
{
    if (_playbackState == PBJVideoPlayerPlaybackStatePlaying)
    {
        [self pause];
    }
}

#pragma mark - KVO

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (context == PBJVideoPlayerObserverContext)
    {

        // Player KVO

    }
    else if (context == PBJVideoPlayerItemObserverContext)
    {

        // PlayerItem KVO

        if ([keyPath isEqualToString:PBJVideoPlayerControllerEmptyBufferKey])
        {
            if (self.playerItem.playbackBufferEmpty)
            {
                self.bufferingState = PBJVideoPlayerBufferingStateDelayed;

                DLog(@"playback buffer is empty");
            }
        }
        else if ([keyPath isEqualToString:PBJVideoPlayerControllerPlayerKeepUpKey])
        {
            if (self.playerItem.playbackLikelyToKeepUp)
            {
                self.bufferingState = PBJVideoPlayerBufferingStateReady;

                DLog(@"playback buffer is likely to keep up");
                if (self.playbackState == PBJVideoPlayerPlaybackStatePlaying)
                {
                    [self playFromCurrentTime];
                }
            }
        }

        AVPlayerStatus status = (AVPlayerStatus) [change[NSKeyValueChangeNewKey] integerValue];
        switch (status)
        {
            case AVPlayerStatusReadyToPlay:
            {
//                _videoView.playerLayer.backgroundColor = [[UIColor blackColor] CGColor];
//                [_videoView.playerLayer setPlayer:self.player];
//                _videoView.playerLayer.hidden = NO;
                break;
            }
            case AVPlayerStatusFailed:
            {
                DLog("playback failed: %@", _playerItem.error);
                _playbackState = PBJVideoPlayerPlaybackStateFailed;
                if (_retries > 0)
                {
                    _retries--;
                    [self forceReload]; // force reload
                }
                break;
            }
            case AVPlayerStatusUnknown:
            default:
                break;
        }
    }
    else
    {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

@end
