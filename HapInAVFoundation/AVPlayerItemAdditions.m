#import "AVPlayerItemAdditions.h"
#import "AVAssetAdditions.h"




@implementation AVPlayerItem (HapInAVFAVPlayerItemAdditions)


- (AVAssetTrack *) hapTrack	{
	AVAsset					*itemAsset = (self==nil) ? nil : [self asset];
	NSArray					*vidTracks = itemAsset.tracks;
	AVAssetTrack			*hapTrack = nil;
	for (AVAssetTrack *trackPtr in vidTracks)	{
		NSArray					*trackFormatDescs = [trackPtr formatDescriptions];
		CMFormatDescriptionRef	desc = (trackFormatDescs==nil || [trackFormatDescs count]<1) ? nil : (__bridge CMFormatDescriptionRef)[trackFormatDescs objectAtIndex:0];
		if (desc != nil)	{
			switch (CMFormatDescriptionGetMediaSubType(desc))	{
			case 'Hap1':
			case 'Hap5':
			case 'HapY':
			case 'HapM':
			case 'HapA':
			case 'Hap7':
				hapTrack = trackPtr;
				break;
			default:
				break;
			}
			if (hapTrack != nil)
				break;
		}
	}
	return hapTrack;
}
- (void) loadHapTrackWithCompletionHandler:(void (^)(AVAssetTrack * _Nullable, NSError * _Nullable))completionHandler {
	[[self asset] loadHapVideoTracksWithCompletionHandler:^(NSArray<AVAssetTrack *> * _Nullable tracks, NSError * _Nullable error) {
		completionHandler(tracks.firstObject, error);
	}];
}


@end
