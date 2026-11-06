//
// ATEBC7Encoder.c
// HapInAVFoundation
//

#include "ATEBC7Encoder.h"
#include "BC7EncoderAdapter.h"

#include <CoreVideo/CoreVideo.h>
#include <stdio.h>
#include <stdlib.h>

struct HapCodecATEBC7Encoder {
	struct HapCodecDXTEncoder base;
	double encodeQuality;
#if defined(DEBUG)
	char description[255];
#endif
};

static void HapCodecATEBC7Destroy(HapCodecDXTEncoderRef encoder)
{
	free(encoder);
}

static OSType HapCodecATEBC7WantedPixelFormat(HapCodecDXTEncoderRef encoder, OSType format)
{
	(void)encoder;
	switch (format) {
		case kCVPixelFormatType_32BGRA:
		case kCVPixelFormatType_32RGBA:
			return format;
		default:
			return kCVPixelFormatType_32RGBA;
	}
}

static int HapCodecATEBC7Encode(
	HapCodecDXTEncoderRef encoder,
	const void *src,
	unsigned int src_bytes_per_row,
	OSType src_pixel_format,
	void *dst,
	unsigned int width,
	unsigned int height)
{
	if (encoder == NULL || encoder->encoder_type != HapDXTEncoderType_ATEBC7)
		return 1;

	int sourceIsBGRA;
	switch (src_pixel_format) {
		case kCVPixelFormatType_32BGRA:
			sourceIsBGRA = 1;
			break;
		case kCVPixelFormatType_32RGBA:
			sourceIsBGRA = 0;
			break;
		default:
			return 2;
	}

	struct HapCodecATEBC7Encoder *recastEncoder = (struct HapCodecATEBC7Encoder *)encoder;
	return HapBC7EncodeImage(
		src,
		src_bytes_per_row,
		sourceIsBGRA,
		dst,
		width,
		height,
		recastEncoder->encodeQuality) == 0 ? 0 : 3;
}

#if defined(DEBUG)
static const char *HapCodecATEBC7Describe(HapCodecDXTEncoderRef encoder)
{
	return ((struct HapCodecATEBC7Encoder *)encoder)->description;
}
#endif

HapCodecDXTEncoderRef HapCodecATEBC7EncoderCreate(OSType pixelFormat, double encodeQuality)
{
	struct HapCodecATEBC7Encoder *encoder = (struct HapCodecATEBC7Encoder *)calloc(1, sizeof(*encoder));
	if (encoder == NULL)
		return NULL;

	encoder->base.destroy_function = HapCodecATEBC7Destroy;
	encoder->base.pixelformat_function = HapCodecATEBC7WantedPixelFormat;
	encoder->base.encode_function = HapCodecATEBC7Encode;
	encoder->base.pad_source_buffers = false;
	encoder->base.can_slice = true;
	encoder->base.encoder_type = HapDXTEncoderType_ATEBC7;
	encoder->encodeQuality = encodeQuality;

#if defined(DEBUG)
	const char *formatString = pixelFormat == kHapCVPixelFormat_RGBA_BC7 ? "RGBA BC7" : "??? BC7";
	snprintf(encoder->description, sizeof(encoder->description), "BC7 %s Encoder (bc7enc_rdo)", formatString);
	encoder->base.describe_function = HapCodecATEBC7Describe;
#else
	(void)pixelFormat;
#endif

	return (HapCodecDXTEncoderRef)encoder;
}
