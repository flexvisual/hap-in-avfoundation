#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workspace_dir="$(cd "$project_dir/.." && pwd)"

check_dependency() {
	local name="$1"
	local required_file="$2"
	local dependency_dir="$workspace_dir/$name"

	if [[ ! -f "$dependency_dir/$required_file" ]]; then
		printf 'error: expected %s at %s\n' "$required_file" "$dependency_dir" >&2
		exit 1
	fi
}

check_dependency snappy CMakeLists.txt
check_dependency hap source/hap.c
check_dependency libsquish squish.h
check_dependency bc7enc_rdo bc7enc.cpp
check_dependency Sparkle Package.swift

scheme="HapInAVFoundation"
if (($# > 0)); then
	scheme="$1"
	shift
fi

exec xcodebuild \
	-project "$project_dir/HapInAVFoundation.xcodeproj" \
	-scheme "$scheme" \
	"$@"
