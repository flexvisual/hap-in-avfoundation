#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#import <AVFoundation/AVFoundation.h>
#import <HapInAVFoundation/HapInAVFoundation.h>
#import "HapMTLPixelBufferTexture.h"
#import "HapMTKView.h"




@interface HapInAVFTestAppDelegate : NSObject <NSApplicationDelegate,NSTabViewDelegate> {
	CADisplayLink				*displayLink;	//	this "drives" rendering
	IBOutlet NSWindow			*window;
	IBOutlet NSTabView			*tabView;
	IBOutlet NSImageView		*imgView;
	IBOutlet HapMTKView			*metalView;
	IBOutlet NSTextField		*statusField;
	
	AVPlayer					*player;
	AVPlayerItem				*playerItem;
	AVPlayerItemVideoOutput		*nativeAVFOutput;	//	this video output is used to play back non-hap content
	AVPlayerItemHapDXTOutput	*hapPlayerOutput; //	works similarly to "nativeAVFOutput"- it's a subclass of AVPlayerItemOutput, you add it to a player item and ask it for new frames (instances of HapDecoderFrame)
	
	id<MTLCommandQueue>			hapTexUploadQueue;
	//	this class uploads the DXT data in a decoded instance of HapDecoderFrame into an id<MTLTexture>.
	HapMTLPixelBufferTexture	*hapMTLTexture;
	// Reuses Metal textures without calling AppKit from texture deallocation.
	HapMTLTexturePool			*hapMTLTexturePool;
}

- (void) loadFileAtPath:(NSString *)n;
- (void) renderCallback;
- (void) displayLinkDidRefresh:(CADisplayLink *)link;
- (void) itemDidPlayToEnd:(NSNotification *)note;

- (HapMTLPixelBufferTexture *) getHapMTLPixelBufferTexture;

@end


