#!/bin/sh
set -eu

cmake_bin=$(command -v cmake 2>/dev/null || true)
if [ -z "$cmake_bin" ]; then
	for candidate in /opt/homebrew/bin/cmake /usr/local/bin/cmake; do
		if [ -x "$candidate" ]; then
			cmake_bin=$candidate
			break
		fi
	done
fi

if [ -z "$cmake_bin" ]; then
	echo "error: CMake 3.10 or later is required to configure Snappy." >&2
	exit 1
fi

cmake_archs=$(printf '%s' "$ARCHS" | tr ' ' ';')
cmake_build_dir="$TEMP_DIR/Snappy"
generated_headers_dir="$DERIVED_FILE_DIR/Snappy"

"$cmake_bin" \
	-S "$PROJECT_DIR/../snappy" \
	-B "$cmake_build_dir" \
	-DCMAKE_OSX_ARCHITECTURES="$cmake_archs" \
	-DCMAKE_OSX_DEPLOYMENT_TARGET="$MACOSX_DEPLOYMENT_TARGET" \
	-DCMAKE_OSX_SYSROOT="$SDKROOT" \
	-DSNAPPY_BUILD_TESTS=OFF \
	-DSNAPPY_BUILD_BENCHMARKS=OFF \
	-DSNAPPY_INSTALL=OFF

mkdir -p "$generated_headers_dir"
cp "$cmake_build_dir/config.h" "$generated_headers_dir/config.h"
cp "$cmake_build_dir/snappy-stubs-public.h" "$generated_headers_dir/snappy-stubs-public.h"
