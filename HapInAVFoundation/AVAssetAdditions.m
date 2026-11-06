#import "AVAssetAdditions.h"
#import "HapCodecSubTypes.h"




@implementation AVAsset (HapInAVFAVAssetAdditions)
- (BOOL) containsHapVideoTrack	{
	NSArray		*hapTracks = [self hapVideoTracks];
	return (hapTracks==nil || [hapTracks count]<1) ? NO : YES;
}
- (NSArray *) hapVideoTracks	{
	NSMutableArray		*returnMe = [NSMutableArray arrayWithCapacity:0];
	NSArray				*vidTracks = self.tracks;
	for (AVAssetTrack *trackPtr in vidTracks)	{
		if ([trackPtr isHapTrack])
			[returnMe addObject:trackPtr];
	}
	return (returnMe==nil || [returnMe count]<1) ? nil : returnMe;
}
- (void) loadHapVideoTracksWithCompletionHandler:(void (^)(NSArray<AVAssetTrack *> * _Nullable, NSError * _Nullable))completionHandler {
	[self loadTracksWithMediaType:AVMediaTypeVideo completionHandler:^(NSArray<AVAssetTrack *> * _Nullable videoTracks, NSError * _Nullable error) {
		if (error != nil || videoTracks == nil) {
			completionHandler(nil, error);
			return;
		}
		NSMutableArray<AVAssetTrack *> *hapTracks = [NSMutableArray array];
		for (AVAssetTrack *track in videoTracks) {
			if (track.isHapTrack)
				[hapTracks addObject:track];
		}
		completionHandler(hapTracks.count == 0 ? nil : [hapTracks copy], nil);
	}];
}
@end




@implementation AVAssetTrack (HapInAVFAVAssetTrackAdditions)
- (BOOL) isHapTrack	{
	BOOL		returnMe = NO;
	NSArray		*trackFormatDescs = [self formatDescriptions];
	for (id desc in trackFormatDescs)	{
		switch (CMFormatDescriptionGetMediaSubType((CMFormatDescriptionRef)desc))	{
		//case 'Hap1':
		//case 'Hap5':
		//case 'HapY':
		case kHapCodecSubType:
		case kHapAlphaCodecSubType:
		case kHapYCoCgCodecSubType:
		case kHapYCoCgACodecSubType:
		case kHapAOnlyCodecSubType:
		case kHap7AlphaCodecSubType:
		case kHapHDRRGBCodecSubType:
			returnMe = YES;
			break;
		default:
			break;
		}
		if (returnMe)
			break;
	}
	return returnMe;
}
@end
