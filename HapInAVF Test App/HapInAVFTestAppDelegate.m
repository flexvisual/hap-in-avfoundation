#import "HapInAVFTestAppDelegate.h"
#import <mach/mach_time.h>
#import <os/log.h>
#import <os/signpost.h>
#import <sys/resource.h>

static os_log_t HapAppPerformanceLog(void) {
	static os_log_t log;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		log = os_log_create("com.vidvox.HapInAVFoundation", "PointsOfInterest");
	});
	return log;
}

@interface HapInAVFTestAppDelegate ()
- (void) runPlaybackControlValidation;
@end



@implementation HapInAVFTestAppDelegate
{
	/** tabIndex is stored here because it's bad behaviour to fetch
	 * it when not in main thread and we need it in the renderCallback
	 **/
	NSInteger selectedTabIndex;
	CVMetalTextureCacheRef metalTextureCache;
	CFTimeInterval performanceWindowStart;
	NSUInteger performanceRefreshCount;
	NSUInteger performanceFrameCount;
	NSUInteger performanceNativeFrameCount;
	float performanceNominalFrameRate;
	NSString *performanceSourceName;
	NSSize performanceImageSize;
	NSInteger performanceTabIndex;
	struct rusage performanceCPUStart;
}


- (id) init {
	self = [super init];
	if (self!=nil)	{
		displayLink = nil;
		player = [[AVPlayer alloc] init];
		[player setActionAtItemEnd:AVPlayerActionAtItemEndPause];
		[player play];
		playerItem = nil;
		nativeAVFOutput = nil;
		hapPlayerOutput = nil;
		
		hapTexUploadQueue = nil;
		hapMTLTexturePool = [[HapMTLTexturePool alloc] init];
		hapMTLTexture = nil;
		performanceWindowStart = 0;
		performanceRefreshCount = 0;
		performanceFrameCount = 0;
		performanceNativeFrameCount = 0;
		performanceNominalFrameRate = 0;
		performanceSourceName = @"unknown";
		performanceImageSize = NSZeroSize;
		performanceTabIndex = -1;

	}
	return self;
}
- (void) awakeFromNib	{
	displayLink = [window displayLinkWithTarget:self selector:@selector(displayLinkDidRefresh:)];
	[displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
	
	//	i want to be the tab view's delegate, so i can respond to tab view changes (and tell the output to enable/disable RGB output)
	[tabView setDelegate:self];
	selectedTabIndex = [tabView indexOfTabViewItem:[tabView selectedTabViewItem]];
	[hapPlayerOutput setOutputAsRGB:selectedTabIndex == 1];
}
- (void) displayLinkDidRefresh:(CADisplayLink *)link {
	++performanceRefreshCount;
	[self renderCallback];
}

- (void) recordPerformanceCallbackWithHapFrame:(BOOL)hasHapFrame {
	if (performanceTabIndex != selectedTabIndex) {
		performanceWindowStart = 0;
		performanceTabIndex = selectedTabIndex;
	}
	CFTimeInterval now = CACurrentMediaTime();
	if (performanceWindowStart == 0) {
		performanceWindowStart = now;
		performanceRefreshCount = 0;
		performanceFrameCount = 0;
		performanceNativeFrameCount = 0;
		getrusage(RUSAGE_SELF, &performanceCPUStart);
	}
	if (hasHapFrame)
		++performanceFrameCount;
	CFTimeInterval elapsed = now - performanceWindowStart;
	if (elapsed < 30.0)
		return;

	struct rusage currentCPUUsage;
	if (getrusage(RUSAGE_SELF, &currentCPUUsage) == 0) {
		double startCPUSeconds = performanceCPUStart.ru_utime.tv_sec + performanceCPUStart.ru_utime.tv_usec / 1000000.0 +
			performanceCPUStart.ru_stime.tv_sec + performanceCPUStart.ru_stime.tv_usec / 1000000.0;
		double currentCPUSeconds = currentCPUUsage.ru_utime.tv_sec + currentCPUUsage.ru_utime.tv_usec / 1000000.0 +
			currentCPUUsage.ru_stime.tv_sec + currentCPUUsage.ru_stime.tv_usec / 1000000.0;
		double expectedFrames = performanceNominalFrameRate > 0 ? elapsed * performanceNominalFrameRate : 0;
		double droppedFramesEstimate = MAX(0, expectedFrames - performanceFrameCount);
		CGSize viewportSize = selectedTabIndex == 1 ? imgView.bounds.size : metalView.drawableSize;
		double frameAspect = performanceImageSize.height > 0 ? performanceImageSize.width / performanceImageSize.height : 0;
		double viewportAspect = viewportSize.height > 0 ? viewportSize.width / viewportSize.height : 0;
		NSLog(@"HAP_PERF file=%@ path=%@ duration_s=%.2f refresh_fps=%.2f hap_fps=%.2f native_fps=%.2f dropped_estimate=%.0f cpu_core_percent=%.1f source_fps=%.3f frame=%0.0fx%0.0f frame_aspect=%.3f viewport=%0.0fx%0.0f viewport_aspect=%.3f texture_objects_created=%lu texture_objects_reused=%lu metal_textures_created=%lu",
			performanceSourceName,
			selectedTabIndex == 1 ? @"NSImage" : @"Metal",
			elapsed,
			performanceRefreshCount / elapsed,
			performanceFrameCount / elapsed,
			performanceNativeFrameCount / elapsed,
			droppedFramesEstimate,
			(currentCPUSeconds - startCPUSeconds) / elapsed * 100.0,
			performanceNominalFrameRate,
			performanceImageSize.width,
			performanceImageSize.height,
			frameAspect,
			viewportSize.width,
			viewportSize.height,
			viewportAspect,
			(unsigned long)hapMTLTexturePool.createdTextureObjectCount,
			(unsigned long)hapMTLTexturePool.reusedTextureObjectCount,
			(unsigned long)hapMTLTexturePool.createdMetalTextureCount);
	}
	performanceWindowStart = now;
	performanceRefreshCount = 0;
	performanceFrameCount = 0;
	performanceNativeFrameCount = 0;
	getrusage(RUSAGE_SELF, &performanceCPUStart);
}
- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
	NSDictionary *environment = NSProcessInfo.processInfo.environment;
	NSString *testFile = environment[@"HAP_PERFORMANCE_TEST_FILE"];
	if (testFile.length == 0)
		return;

	NSString *testPath = environment[@"HAP_PERFORMANCE_TEST_PATH"];
	NSInteger testTabIndex = [testPath isEqualToString:@"NSImage"] ? 1 : 0;
	[tabView selectTabViewItemAtIndex:testTabIndex];
	selectedTabIndex = testTabIndex;
	performanceTabIndex = testTabIndex;
	performanceSourceName = testFile.lastPathComponent;
	[self loadFileAtPath:testFile];

	if ([environment[@"HAP_PLAYBACK_CONTROL_TEST"] isEqualToString:@"1"]) {
		[self runPlaybackControlValidation];
		return;
	}

	NSTimeInterval testDuration = [environment[@"HAP_PERFORMANCE_TEST_DURATION"] doubleValue];
	if (testDuration <= 0)
		testDuration = 30.0;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((testDuration + 10.0) * NSEC_PER_SEC)),
		dispatch_get_main_queue(), ^{
			NSLog(@"HAP_PERF_TEST_DONE path=%@", self->selectedTabIndex == 1 ? @"NSImage" : @"Metal");
			[self->player pause];
			[NSApp terminate:nil];
		});
}

- (void) runPlaybackControlValidation {
	NSLog(@"HAP_CONTROL_TEST pause");
	[player pause];
	CFTimeInterval pausedAt = CACurrentMediaTime();
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
		NSLog(@"HAP_CONTROL_TEST paused_rate=%.3f elapsed_s=%.2f", self->player.rate, CACurrentMediaTime() - pausedAt);
		CMTime seekTime = CMTimeMakeWithSeconds(CMTimeGetSeconds(self->player.currentItem.duration) / 2.0, 600);
		NSLog(@"HAP_CONTROL_TEST seek_to_midpoint");
		[self->player seekToTime:seekTime toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL finished) {
			NSLog(@"HAP_CONTROL_TEST seek_midpoint_finished=%d", finished);
			[self->player setRate:1.0];
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
				NSLog(@"HAP_CONTROL_TEST restart_to_zero");
				[self->player seekToTime:kCMTimeZero toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL restarted) {
					NSLog(@"HAP_CONTROL_TEST restart_finished=%d", restarted);
					[self->player setRate:1.0];
					self->performanceWindowStart = 0;
					dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 35 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
						NSLog(@"HAP_CONTROL_TEST_DONE");
						[self->player pause];
						[NSApp terminate:nil];
					});
				}];
			});
		}];
	});
}
- (void)applicationWillTerminate:(NSNotification *)aNotification {
	[displayLink invalidate];
	displayLink = nil;
	if (metalTextureCache != NULL) {
		CVMetalTextureCacheFlush(metalTextureCache, 0);
		CFRelease(metalTextureCache);
		metalTextureCache = NULL;
	}
}


- (void) openDocument:(id)sender	{
	NSOpenPanel		*openPanel = [NSOpenPanel openPanel];
	NSUserDefaults	*def = [NSUserDefaults standardUserDefaults];
	NSString		*openPanelDir = [def objectForKey:@"openPanelDir"];
	if (openPanelDir==nil)
		openPanelDir = [@"~/" stringByExpandingTildeInPath];
	[openPanel setDirectoryURL:[NSURL fileURLWithPath:openPanelDir]];
	[openPanel
		beginSheetModalForWindow:window
		completionHandler:^(NSInteger result)	{
		NSString		*path = (result!=NSModalResponseOK) ? nil : [[openPanel URL] path];
			if (path != nil)	{
				NSUserDefaults		*udef = [NSUserDefaults standardUserDefaults];
				[udef setObject:[path stringByDeletingLastPathComponent] forKey:@"openPanelDir"];
				[udef synchronize];
				self->performanceSourceName = [path lastPathComponent];
			}
			//[self loadFileAtPath:path];
			dispatch_async(dispatch_get_main_queue(), ^{
				[self loadFileAtPath:path];
			});
		}];
}


- (void) loadFileAtPath:(NSString *)n	{
	NSLog(@"%s ... %@",__func__,n);
	if (n != nil)
		performanceSourceName = [n lastPathComponent];
	performanceWindowStart = 0;
	performanceTabIndex = selectedTabIndex;
	//	make an asset
	NSURL				*newURL = (n==nil) ? nil : [NSURL fileURLWithPath:n];
	AVAsset				*newAsset = (newURL==nil) ? nil : [AVAsset assetWithURL:newURL];
	//	make a player item
	AVPlayerItem		*newPlayerItem = (newAsset==nil) ? nil : [[AVPlayerItem alloc] initWithAsset:newAsset];
	if (newPlayerItem == nil)	{
		NSLog(@"\t\terr: couldn't make AVPlayerItem in %s",__func__);
		return;
	}
	//	update the status label
	[newAsset loadTracksWithMediaType:AVMediaTypeVideo completionHandler:^(NSArray<AVAssetTrack *> * _Nullable videoTracks, NSError * _Nullable error) {
		if (error != nil) {
			NSLog(@"Unable to load video tracks for %@: %@", newURL, error);
			return;
		}
		AVAssetTrack *videoTrack = videoTracks.firstObject;
		dispatch_async(dispatch_get_main_queue(), ^{
			if (self->playerItem == newPlayerItem)
				self->performanceNominalFrameRate = videoTrack.nominalFrameRate;
		});
		NSArray *trackFormatDescs = videoTrack.formatDescriptions;
		CMFormatDescriptionRef desc = trackFormatDescs.firstObject == nil ? NULL : (__bridge CMFormatDescriptionRef)trackFormatDescs.firstObject;
		if (desc == NULL) {
			NSLog(@"No video format description found for %@", newURL);
			return;
		}
		OSType fourcc = CMFormatDescriptionGetMediaSubType(desc);
		char destChars[5] = {
			(fourcc >> 24) & 0xFF,
			(fourcc >> 16) & 0xFF,
			(fourcc >> 8) & 0xFF,
			fourcc & 0xFF,
			0
		};
		NSString *codecName = [NSString stringWithCString:destChars encoding:NSASCIIStringEncoding];
		dispatch_async(dispatch_get_main_queue(), ^{
			if (self->playerItem == newPlayerItem)
				[self->statusField setStringValue:[NSString stringWithFormat:@"codec sub-type is '%@'", codecName]];
		});
	}];
	
	@synchronized (self)	{
		//	if there's an output, remove it from the "old" item
		if (nativeAVFOutput != nil) {
			if (playerItem != nil)
				[playerItem removeOutput:nativeAVFOutput];
		}
		//	else there's no output- create one
		else	{
			NSDictionary		*pba = @{
				(NSString*)kCVPixelBufferPixelFormatTypeKey: @( kCVPixelFormatType_32BGRA ),
				(NSString*)kCVPixelBufferMetalCompatibilityKey: @( YES )
			};
			nativeAVFOutput = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:pba];
			[nativeAVFOutput setSuppressesPlayerRendering:YES];
		}
		
		//	if there's a hap output, remove it from the "old" item
		if (hapPlayerOutput != nil)	{
			if (playerItem != nil)
				[playerItem removeOutput:hapPlayerOutput];
		}
		//	else there's no hap output- create one
		else	{
			hapPlayerOutput = [[AVPlayerItemHapDXTOutput alloc] init];
			[hapPlayerOutput setSuppressesPlayerRendering:YES];
			//	The CPU inspection tab needs RGB data; Metal consumes compressed textures directly.
			[hapPlayerOutput setOutputAsRGB:(selectedTabIndex==1)];
		}
		
		//	unregister as an observer for the "old" item's play-to-end notifications
		NSNotificationCenter	*nc = [NSNotificationCenter defaultCenter];
		if (playerItem != nil)
			[nc removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:playerItem];
		
		//	add the outputs to the new player item
		[newPlayerItem addOutput:nativeAVFOutput];
		[newPlayerItem addOutput:hapPlayerOutput];
		//	tell the player to start playing the new player item
		if ([NSThread isMainThread])
			[player replaceCurrentItemWithPlayerItem:newPlayerItem];
		else
			[player performSelectorOnMainThread:@selector(replaceCurrentItemWithPlayerItem:) withObject:newPlayerItem waitUntilDone:YES];
		//	register to receive notifications that the new player item has played to its end
		if (newPlayerItem != nil)
			[nc addObserver:self selector:@selector(itemDidPlayToEnd:) name:AVPlayerItemDidPlayToEndTimeNotification object:newPlayerItem];
		
		//	release the "old" player item, retain a ptr to the "new" player item
		playerItem = (newPlayerItem==nil) ? nil : newPlayerItem;
		
		[player setRate:1.0];
	}
}


//	this is called when you change the tabs in the tab view
- (void) tabView:(NSTabView *)tv didSelectTabViewItem:(NSTabViewItem *)item {
	NSInteger		selIndex = [tv indexOfTabViewItem:item];
	selectedTabIndex = [tabView indexOfTabViewItem:[tabView selectedTabViewItem]];
	performanceWindowStart = 0;
	performanceTabIndex = selectedTabIndex;
	//	The CPU inspection tab needs RGB output; Metal displays compressed textures directly.
	if (selIndex==1)
		[hapPlayerOutput setOutputAsRGB:YES];
	else
		[hapPlayerOutput setOutputAsRGB:NO];
}


//	this is called by the displaylink's C callback- this drives rendering
- (void) renderCallback {
	@synchronized (self)	{
		//	try to get a hap decoder frame- it returns a nil quickly if the player it's attached to doesn't have a hap track.
		CMTime					outputTime = [hapPlayerOutput itemTimeForMachAbsoluteTime:mach_absolute_time()];
		HapDecoderFrame			*dxtFrame = [hapPlayerOutput allocFrameClosestToTime:outputTime];
		//HapDecoderFrame			*dxtFrame = [hapPlayerOutput allocFrameForTime:outputTime];
		if (dxtFrame != nil)
			performanceImageSize = dxtFrame.imgSize;
		[self recordPerformanceCallbackWithHapFrame:dxtFrame != nil];
		if (dxtFrame!=nil)	{
			NSSize					imgSize = [dxtFrame imgSize];
			if (selectedTabIndex == 1)	{
				//	if the frame has RGB data attached to it, make an NSBitmapImageRep & NSImage from the data, then draw it in the NSImageView
				void				*rgbData = [dxtFrame rgbData];
				size_t				rgbDataSize = [dxtFrame rgbDataSize];
				if (rgbData==nil)	{
					NSLog(@"\t\terr: rgb data nil in %s",__func__);
				}
				else	{
					NSBitmapImageRep	*bitmapRep = [[NSBitmapImageRep alloc]
						initWithBitmapDataPlanes:NULL
						pixelsWide:(NSUInteger)imgSize.width
						pixelsHigh:(NSUInteger)imgSize.height
						bitsPerSample:8
						samplesPerPixel:4
						hasAlpha:YES
						isPlanar:NO
						colorSpaceName:NSCalibratedRGBColorSpace
						bitmapFormat:0
						bytesPerRow:rgbDataSize/(NSUInteger)imgSize.height
						bitsPerPixel:32];
					if (bitmapRep==nil)
						NSLog(@"\t\terr: bitmap rep nil, %s",__func__);
					else	{
						memcpy([bitmapRep bitmapData], rgbData, rgbDataSize);
						NSImage				*newImg = [[NSImage alloc] initWithSize:imgSize];
						[newImg addRepresentation:bitmapRep];
						//	draw the NSImage in the view
						dispatch_async(dispatch_get_main_queue(), ^{
							[self->imgView setImage:newImg];
						});
						
						newImg = nil;
						bitmapRep = nil;
					}
				}
			}
			else {
				id<MTLDevice>			viewDevice = metalView.device;
				
				//	make sure we have an upload queue that works with the view's device...
				if (hapTexUploadQueue != nil && hapTexUploadQueue.device != viewDevice)
					hapTexUploadQueue = nil;
				if (hapTexUploadQueue == nil)	{
					hapTexUploadQueue = [viewDevice newCommandQueue];
				}
				
				//	if we have a texture, but its frame differs from the decoded frame we're going to try drawing, just free it- the view that draws it is responsible for retaining its own copy.  we need to start uploading this new image data to a new texture ("new"- likely pooled).
				if (hapMTLTexture != nil && hapMTLTexture.frame != dxtFrame)	{
					hapMTLTexture = nil;
				}
				
				//	if we still have a hap metal texture...
				if (hapMTLTexture != nil)	{
					//	intentionally blank- the image data has already been uploaded to the texture, and will be passed to the view when the commnad buffer pushing the data to the GPU completes
				}
				//	else we don't have a hap metal texture- we need to create one and populate it...
				else	{
					hapMTLTexture = [self getHapMTLPixelBufferTexture];
					
					//	when the command buffer that populates the texture completes, pass the texture to the view for display
					id<MTLCommandBuffer>	cmdBuffer = [hapTexUploadQueue commandBuffer];
					[hapMTLTexture populateWithHapDecoderFrame:dxtFrame inCommandBuffer:cmdBuffer];
					os_log_t performanceLog = HapAppPerformanceLog();
					[cmdBuffer addCompletedHandler:^(id<MTLCommandBuffer> completedBuffer) {
						if (completedBuffer.status == MTLCommandBufferStatusCompleted &&
							completedBuffer.GPUEndTime >= completedBuffer.GPUStartTime) {
							double gpuMilliseconds = (completedBuffer.GPUEndTime - completedBuffer.GPUStartTime) * 1000.0;
							os_signpost_event_emit(performanceLog, OS_SIGNPOST_ID_EXCLUSIVE, "Compressed texture upload GPU", "gpu_ms=%{public}.3f", gpuMilliseconds);
						}
					}];
					HapMTLPixelBufferTexture *textureToDisplay = hapMTLTexture;
					[cmdBuffer addCompletedHandler:^(id<MTLCommandBuffer> completedCB)	{
						dispatch_async(dispatch_get_main_queue(), ^{
							[self->metalView displayPixelBufferTexture:textureToDisplay flipped:NO];
						});
					}];
					[cmdBuffer commit];
				}
			}
			
			dxtFrame = nil;
		}

		//	try to get a CV pixel buffer (returns immediately if we're not using the native AVF output side of things: this chunk of code only executes if we're playing back NON-hap video files supported by AVFoundation!)
		CMTime					frameTime = [nativeAVFOutput itemTimeForMachAbsoluteTime:mach_absolute_time()];
		if (nativeAVFOutput!=nil && [nativeAVFOutput hasNewPixelBufferForItemTime:frameTime])	{
			CMTime					frameDisplayTime = kCMTimeZero;
			CVPixelBufferRef		nativeAVFPB = [nativeAVFOutput copyPixelBufferForItemTime:frameTime itemTimeForDisplay:&frameDisplayTime];
			if (nativeAVFPB==NULL)
				NSLog(@"\t\tERR: unable to copy pixel buffer from nativeAVFOutput");
			else	{
				++performanceNativeFrameCount;
				//	Use CPU display for inspection; otherwise display through Metal.
				if (selectedTabIndex==1)	{
					size_t				pbBytesPerRow = CVPixelBufferGetBytesPerRow(nativeAVFPB);
					NSSize				imgSize = NSMakeSize(CVPixelBufferGetWidth(nativeAVFPB), CVPixelBufferGetHeight(nativeAVFPB));
					NSBitmapImageRep	*bitmapRep = [[NSBitmapImageRep alloc]
						initWithBitmapDataPlanes:NULL
						pixelsWide:(NSUInteger)imgSize.width
						pixelsHigh:(NSUInteger)imgSize.height
						bitsPerSample:8
						samplesPerPixel:4
						hasAlpha:YES
						isPlanar:NO
						colorSpaceName:NSCalibratedRGBColorSpace
						bitmapFormat:0
						bytesPerRow:pbBytesPerRow
						bitsPerPixel:32];
					if (bitmapRep==nil)
						NSLog(@"\t\terr: bitmap rep nil, %s",__func__);
					else	{
						CVPixelBufferLockBaseAddress(nativeAVFPB, kCVPixelBufferLock_ReadOnly);
						size_t				bitmapBytesPerRow = [bitmapRep bytesPerRow];
						size_t				minBytesPerRow = fminl(pbBytesPerRow, bitmapBytesPerRow);
						void				*readAddr = CVPixelBufferGetBaseAddress(nativeAVFPB);
						void				*writeAddr = [bitmapRep bitmapData];
						for (int i=0; i<imgSize.height; ++i)	{
							memcpy(writeAddr, readAddr, minBytesPerRow);
							writeAddr += bitmapBytesPerRow;
							readAddr += pbBytesPerRow;
						}
						CVPixelBufferUnlockBaseAddress(nativeAVFPB, kCVPixelBufferLock_ReadOnly);
						
						NSImage				*newImg = [[NSImage alloc] initWithSize:imgSize];
						[newImg addRepresentation:bitmapRep];
						//	draw the NSImage in the view
						[imgView setImage:newImg];
					
						newImg = nil;
						bitmapRep = nil;
					}
					
				}
				//	else we're using metal to display the buffer...
				else {
					
					if (metalTextureCache==NULL)	{
						CVReturn		cvReturn = CVMetalTextureCacheCreate(
							kCFAllocatorDefault,
							nil,
							metalView.device,
							nil,
							&metalTextureCache);
						if (cvReturn != kCVReturnSuccess)	{
							NSLog(@"\t\terr %d at CVMetalTextureCacheCreate(). Abort render.",cvReturn);
							return;
						}
					}
					CVMetalTextureRef		metalTextureRef = NULL;
					CGSize			textureSize = CGSizeMake(CVPixelBufferGetWidth(nativeAVFPB), CVPixelBufferGetHeight(nativeAVFPB));
					CVReturn		cvReturn = CVMetalTextureCacheCreateTextureFromImage(
						kCFAllocatorDefault,
						metalTextureCache,
						nativeAVFPB,
						nil,
						metalView.colorPixelFormat,
						textureSize.width,
						textureSize.height,
						0,
						&metalTextureRef);
					if (cvReturn == kCVReturnSuccess)	{
						[metalView displayCVMetalTextureRef:metalTextureRef flipped:NO];
						CVBufferRelease(metalTextureRef);
					}
					else	{
						NSLog(@"\t\terr %d at CVMetalTextureCacheCreateTextureFromImage()",cvReturn);
					}
					
				}
				
				CVPixelBufferRelease(nativeAVFPB);
			}
		}
		
		if (metalTextureCache != NULL)
			CVMetalTextureCacheFlush(metalTextureCache, 0);
	}
	
}
- (void) itemDidPlayToEnd:(NSNotification *)note	{
	@synchronized (self)	{
		[player seekToTime:kCMTimeZero];
		[player setRate:1.0];
	}
}


- (HapMTLPixelBufferTexture *) getHapMTLPixelBufferTexture	{
	return [hapMTLTexturePool dequeueTextureForDevice:metalView.device];
}


@end
