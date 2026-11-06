#include "BC7EncoderAdapter.h"

#include "bc7enc.h"

#include <algorithm>
#include <cmath>
#include <limits>
#include <mutex>

namespace {

std::once_flag bc7Initialization;

void initializeBC7Encoder()
{
	bc7enc_compress_block_init();
}

}

extern "C" int HapBC7EncodeImage(
	const void *sourcePixels,
	size_t sourceBytesPerRow,
	int sourceIsBGRA,
	void *destinationBlocks,
	unsigned int width,
	unsigned int height,
	double quality)
{
	if (sourcePixels == nullptr || destinationBlocks == nullptr || width == 0 || height == 0)
		return 1;
	const size_t maxSize = std::numeric_limits<size_t>::max();
	if (static_cast<size_t>(width) > maxSize / 4)
		return 1;

	const size_t sourceRowBytes = static_cast<size_t>(width) * 4;
	if (sourceBytesPerRow < sourceRowBytes)
		return 1;
	if (height > 1 &&
		sourceBytesPerRow > (maxSize - sourceRowBytes) / (static_cast<size_t>(height) - 1))
		return 1;

	const size_t blocksWide = width / 4 + (width % 4 != 0);
	const size_t blocksHigh = height / 4 + (height % 4 != 0);
	if (blocksWide > maxSize / 16 ||
		blocksHigh > maxSize / (blocksWide * 16))
		return 1;

	if (!std::isfinite(quality))
		quality = 0.5;
	quality = std::max(0.0, std::min(1.0, quality));

	bc7enc_compress_block_params params;
	bc7enc_compress_block_params_init(&params);
	// Spend increasing search effort as the framework's normalized quality rises.
	params.m_max_partitions = 1 + static_cast<uint32_t>(quality * (BC7ENC_MAX_PARTITIONS - 1) + 0.5);
	params.m_uber_level = static_cast<uint32_t>(quality * BC7ENC_MAX_UBER_LEVEL + 0.5);
	params.m_try_least_squares = quality >= 0.25;

	std::call_once(bc7Initialization, initializeBC7Encoder);

	const uint8_t *source = static_cast<const uint8_t *>(sourcePixels);
	uint8_t *destination = static_cast<uint8_t *>(destinationBlocks);
	uint8_t blockPixels[BC7ENC_BLOCK_SIZE * 4];

	for (size_t blockY = 0; blockY < blocksHigh; ++blockY) {
		const size_t blockStartY = blockY * 4;
		for (size_t blockX = 0; blockX < blocksWide; ++blockX) {
			const size_t blockStartX = blockX * 4;
			for (size_t pixelY = 0; pixelY < 4; ++pixelY) {
				const size_t sourceY = blockStartY + std::min(pixelY, static_cast<size_t>(height) - 1 - blockStartY);
				const uint8_t *sourceRow = source + sourceY * sourceBytesPerRow;
				for (size_t pixelX = 0; pixelX < 4; ++pixelX) {
					const size_t sourceX = blockStartX + std::min(pixelX, static_cast<size_t>(width) - 1 - blockStartX);
					const uint8_t *sourcePixel = sourceRow + sourceX * 4;
					uint8_t *blockPixel = blockPixels + (pixelY * 4 + pixelX) * 4;
					if (sourceIsBGRA) {
						blockPixel[0] = sourcePixel[2];
						blockPixel[1] = sourcePixel[1];
						blockPixel[2] = sourcePixel[0];
					}
					else {
						blockPixel[0] = sourcePixel[0];
						blockPixel[1] = sourcePixel[1];
						blockPixel[2] = sourcePixel[2];
					}
					blockPixel[3] = sourcePixel[3];
				}
			}

			uint8_t *block = destination + (blockY * blocksWide + blockX) * 16;
			bc7enc_compress_block(block, blockPixels, &params);
		}
	}

	return 0;
}
