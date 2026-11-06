#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN


/// convenience method that makes it easier to recognize AVFoundation resources that contain hap video data
@interface AVPlayerItem (HapInAVFAVPlayerItemAdditions)

/**
Asynchronously loads and returns the item's first video track containing Hap data.
*/
- (void) loadHapTrackWithCompletionHandler:(void (^)(AVAssetTrack * _Nullable track, NSError * _Nullable error))completionHandler;

/**
Extends the AVPlayerItem class so instances will return their asset track- if any- that contains video data compressed using the hap video codec.
*/
- (AVAssetTrack * _Nullable) hapTrack;

@end

NS_ASSUME_NONNULL_END
