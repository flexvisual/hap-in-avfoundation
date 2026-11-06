#ifndef Hap_BC7EncoderAdapter_h
#define Hap_BC7EncoderAdapter_h

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

int HapBC7EncodeImage(
	const void *sourcePixels,
	size_t sourceBytesPerRow,
	int sourceIsBGRA,
	void *destinationBlocks,
	unsigned int width,
	unsigned int height,
	double quality);

#ifdef __cplusplus
}
#endif

#endif
