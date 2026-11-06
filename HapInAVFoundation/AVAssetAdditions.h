#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN


/**
Class additions to AVAsset that simplify recognizing media containing Hap data
*/
@interface AVAsset (HapInAVFAVAssetAdditions)
/**
Loads video tracks and returns only tracks containing Hap data.
*/
- (void) loadHapVideoTracksWithCompletionHandler:(void (^)(NSArray<AVAssetTrack *> * _Nullable tracks, NSError * _Nullable error))completionHandler;
/**
Returns a YES if the receiver contains a video track with Hap data.
*/
- (BOOL) containsHapVideoTrack;
/**
Returns an array populated with instances of AVAssetTrack that contain Hap data.
*/
- (NSArray<AVAssetTrack *> * _Nullable) hapVideoTracks;
@end

NS_ASSUME_NONNULL_END



/**
Class additions to AVAssetTrack that simplify recognizing tracks containing Hap data
*/
@interface AVAssetTrack (HapInAVFAVAssetTrackAdditions)
/**
Returns a YES if the receiver contains video data compressed using the Hap codec.
*/
- (BOOL) isHapTrack;
@end
