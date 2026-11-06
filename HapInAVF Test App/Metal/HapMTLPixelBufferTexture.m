//
//  HapMTLPixelBufferTexture.m
//  HapInAVF Test App
//
//  Created by testadmin on 6/8/23.
//  Copyright © 2023 Vidvox. All rights reserved.
//

#import "HapMTLPixelBufferTexture.h"
#import <Metal/Metal.h>
#import <os/log.h>
#import <os/signpost.h>

#import "Utility.h"




//	i'm #defining this here explicitly so i can use it as a variable in the source code, with the intent of conveying to the user that a)- this is why there's a "multiply by four" step and b)- that this value shouldn't be treated as a variable at runtime.
#define DXT_BLOCK_SIZE 4

static os_log_t HapTexturePerformanceLog(void) {
	static os_log_t log;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		log = os_log_create("com.vidvox.HapInAVFoundation", "PointsOfInterest");
	});
	return log;
}




@interface HapMTLPixelBufferTexture ()

@property (strong,readwrite) id<MTLDevice> device;
@property (strong,readwrite) id<MTLTexture> textureA;
@property (strong,readwrite) id<MTLTexture> textureB;

@property (weak,readwrite) HapDecoderFrame * frame;

@property (assign,readwrite) OSType codecSubType;
@property (assign,readwrite) CGSize dxtImgSize;
@property (assign,readwrite) CGSize imgSize;
@property (weak) HapMTLTexturePool *poolOwner;

@end


@interface HapMTLTexturePool ()
@property (strong) NSMutableArray<HapMTLPixelBufferTexture *> *availableTextures;
- (void) recordMetalTextureAllocation;
@end



@implementation HapMTLPixelBufferTexture


+ (instancetype) createWithDevice:(id<MTLDevice>)inDevice	{
	return [[HapMTLPixelBufferTexture alloc] initWithDevice:inDevice];
}


+ (MTLPixelFormat) pixelFormatForHapTextureFormat:(enum HapTextureFormat)n	{
	switch (n)	{
	case HapTextureFormat_RGB_DXT1:					return MTLPixelFormatBC1_RGBA;
	case HapTextureFormat_RGBA_DXT5:				return MTLPixelFormatBC3_RGBA;
	case HapTextureFormat_YCoCg_DXT5:				return MTLPixelFormatBC3_RGBA;
	case HapTextureFormat_A_RGTC1:					return MTLPixelFormatBC4_RUnorm;
	case HapTextureFormat_RGBA_BPTC_UNORM:			return MTLPixelFormatBC7_RGBAUnorm;
	case HapTextureFormat_RGB_BPTC_UNSIGNED_FLOAT:	return MTLPixelFormatBC6H_RGBUfloat;
	case HapTextureFormat_RGB_BPTC_SIGNED_FLOAT:	return MTLPixelFormatBC6H_RGBFloat;
	}
	NSLog(@"ERR: unrecognized texture format (%X) in %s",n,__func__);
	return MTLPixelFormatBGRA8Unorm;
}


- (instancetype) initWithDevice:(id<MTLDevice>)inDevice	{
	self = [super init];
	
	if (inDevice == nil)
		self = nil;
	
	if (self != nil)	{
		_device = inDevice;
		_textureA = nil;
		_textureB = nil;
		
		_frame = nil;
		
		_codecSubType = 0x00;
		_dxtImgSize = CGSizeMake(0,0);
		_imgSize = CGSizeMake(0,0);
	}
	
	return self;
}


- (void)recycleForReuse {
    HapMTLTexturePool *poolOwner = _poolOwner;
    if (poolOwner != nil)
    	[poolOwner recycleTexture:self];
}


- (void) populateWithHapDecoderFrame:(HapDecoderFrame *)n inCommandBuffer:(id<MTLCommandBuffer>)inCB	{
	if (n == nil)
		return;
	os_log_t performanceLog = HapTexturePerformanceLog();
	os_signpost_id_t uploadID = os_signpost_id_generate(performanceLog);
	os_signpost_interval_begin(performanceLog, uploadID, "Compressed texture upload CPU");
	
	_frame = n;
	enum HapTextureFormat		*dxtTextureFormats = n.dxtTextureFormats;
	NSSize		dxtTextureSize = n.dxtImgSize;
	NSSize		imgSize = n.imgSize;
	//	if we have existing textures, check to make sure that they have the correct format and dimensions- if they don't, delete them
	if (_textureA != nil)	{
		if (n.dxtPlaneCount < 1)	{
			_textureA = nil;
		}
		else	{
			MTLPixelFormat		planeFmt = [HapMTLPixelBufferTexture pixelFormatForHapTextureFormat:*(dxtTextureFormats+0)];
			if (planeFmt != _textureA.pixelFormat)	{
				_textureA = nil;
			}
			else	{
				if (!NSEqualSizes(dxtTextureSize, NSMakeSize(_textureA.width, _textureA.height)))	{
					_textureA = nil;
				}
			}
		}
	}
	if (_textureB != nil)	{
		if (n.dxtPlaneCount < 2)	{
			_textureB = nil;
		}
		else	{
			MTLPixelFormat		planeFmt = [HapMTLPixelBufferTexture pixelFormatForHapTextureFormat:*(dxtTextureFormats+1)];
			if (planeFmt != _textureB.pixelFormat)	{
				_textureB = nil;
			}
			else	{
				if (!NSEqualSizes(dxtTextureSize, NSMakeSize(_textureB.width, _textureB.height)))	{
					_textureB = nil;
				}
			}
		}
	}
	
	//	if we're missing textures, create them
	if (_textureA == nil)	{
		if (n.dxtPlaneCount >= 1)	{
			MTLPixelFormat		planeFmt = [HapMTLPixelBufferTexture pixelFormatForHapTextureFormat:*(dxtTextureFormats+0)];
			//	make a texture from that buffer!
			MTLTextureDescriptor	*desc = [[MTLTextureDescriptor alloc] init];
			desc.textureType = MTLTextureType2D;
			desc.pixelFormat = planeFmt;
			desc.width = round(dxtTextureSize.width);
			desc.height = round (dxtTextureSize.height);
			desc.depth = 1;
			//desc.resourceOptions = MTLResourceStorageModePrivate;	//	GPU-only
			desc.resourceOptions = MTLResourceStorageModeManaged;
			//desc.storageMode = MTLStorageModePrivate;	//	GPU-only
			desc.storageMode = MTLStorageModeManaged;
			desc.usage = MTLTextureUsageShaderRead;
			//desc.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite | MTLTextureUsagePixelFormatView;
			_textureA = [_device newTextureWithDescriptor:desc];
			if (_textureA != nil)
				[_poolOwner recordMetalTextureAllocation];
		}
	}
	if (_textureB == nil)	{
		if (n.dxtPlaneCount >= 2)	{
			MTLPixelFormat		planeFmt = [HapMTLPixelBufferTexture pixelFormatForHapTextureFormat:*(dxtTextureFormats+1)];
			//	make a texture from that buffer!
			MTLTextureDescriptor	*desc = [[MTLTextureDescriptor alloc] init];
			desc.textureType = MTLTextureType2D;
			desc.pixelFormat = planeFmt;
			desc.width = round(dxtTextureSize.width);
			desc.height = round (dxtTextureSize.height);
			desc.depth = 1;
			//desc.resourceOptions = MTLResourceStorageModePrivate;	//	GPU-only
			desc.resourceOptions = MTLResourceStorageModeManaged;
			//desc.storageMode = MTLStorageModePrivate;	//	GPU-only
			desc.storageMode = MTLStorageModeManaged;
			desc.usage = MTLTextureUsageShaderRead;
			//desc.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite | MTLTextureUsagePixelFormatView;
			_textureB = [_device newTextureWithDescriptor:desc];
			if (_textureB != nil)
				[_poolOwner recordMetalTextureAllocation];
		}
	}
	
	size_t			*dxtMinDataSizes = n.dxtMinDataSizes;
	void			**dxtDatas = n.dxtDatas;
	//	push the image data to the textures
	if (_textureA != nil)	{
		//NSLog(@"\t\tdxtMinDataSize is %ld, bytes per row is %ld",*(dxtMinDataSizes+0),*(dxtMinDataSizes+0)/round(dxtTextureSize.height));
		//uint32_t		bytesForPlane = dxtBytesForDimensions(dxtTextureSize.width, dxtTextureSize.height, n.codecSubType);
		//NSLog(@"\t\tbytesForPlane is %ld",bytesForPlane);
		[_textureA
			replaceRegion:MTLRegionMake2D(0,0,round(dxtTextureSize.width),round(dxtTextureSize.height))
			mipmapLevel:0
			withBytes:*(dxtDatas+0)
			bytesPerRow:*(dxtMinDataSizes+0) / round(dxtTextureSize.height) * DXT_BLOCK_SIZE];
	}
	if (_textureB != nil)	{
		[_textureB
			replaceRegion:MTLRegionMake2D(0,0,round(dxtTextureSize.width),round(dxtTextureSize.height))
			mipmapLevel:0
			withBytes:*(dxtDatas+1)
			bytesPerRow:*(dxtMinDataSizes+1) / round(dxtTextureSize.height) * DXT_BLOCK_SIZE];
	}
	os_signpost_interval_end(performanceLog, uploadID, "Compressed texture upload CPU");
	
	_codecSubType = n.codecSubType;
	_dxtImgSize = CGSizeMake(round(dxtTextureSize.width), round(dxtTextureSize.height));
	_imgSize = CGSizeMake(round(imgSize.width), round(imgSize.height));
	
	if (_textureA != nil || _textureB != nil)	{
		if (inCB != nil)	{
			id<MTLBlitCommandEncoder>		blitEncoder = [inCB blitCommandEncoder];
			if (_textureA != nil)	{
				[blitEncoder synchronizeResource:_textureA];
			}
			if (_textureB != nil)	{
				[blitEncoder synchronizeResource:_textureB];
			}
			[blitEncoder endEncoding];
		}
	}
}

@end


@implementation HapMTLTexturePool
{
	NSUInteger _createdTextureObjectCount;
	NSUInteger _reusedTextureObjectCount;
	NSUInteger _createdMetalTextureCount;
}

- (instancetype)init {
	self = [super init];
	if (self != nil)
		_availableTextures = [NSMutableArray array];
	return self;
}

- (HapMTLPixelBufferTexture *)dequeueTextureForDevice:(id<MTLDevice>)device {
	HapMTLPixelBufferTexture *texture = nil;
	@synchronized (self) {
		NSUInteger textureIndex = [_availableTextures indexOfObjectPassingTest:^BOOL(HapMTLPixelBufferTexture *candidate, NSUInteger index, BOOL *stop) {
			return candidate.device == device;
		}];
		if (textureIndex != NSNotFound) {
			texture = _availableTextures[textureIndex];
			[_availableTextures removeObjectAtIndex:textureIndex];
			++_reusedTextureObjectCount;
		}
		else {
			++_createdTextureObjectCount;
		}
	}
	if (texture == nil)
		texture = [[HapMTLPixelBufferTexture alloc] initWithDevice:device];
	texture.poolOwner = self;
	return texture;
}

- (void)recycleTexture:(HapMTLPixelBufferTexture *)texture {
	@synchronized (self) {
		[_availableTextures addObject:texture];
	}
}

- (void)recordMetalTextureAllocation {
	@synchronized (self) {
		++_createdMetalTextureCount;
	}
}

- (NSUInteger)createdTextureObjectCount {
	@synchronized (self) {
		return _createdTextureObjectCount;
	}
}

- (NSUInteger)reusedTextureObjectCount {
	@synchronized (self) {
		return _reusedTextureObjectCount;
	}
}

- (NSUInteger)createdMetalTextureCount {
	@synchronized (self) {
		return _createdMetalTextureCount;
	}
}

@end
