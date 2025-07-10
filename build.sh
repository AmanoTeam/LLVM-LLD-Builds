#!/bin/bash

set -eu

declare -r workdir="${PWD}"

declare -r llvm_version='20.1.8'

declare -r llvm_tarball='/tmp/llvm.tar.gz'
declare -r llvm_directory="/tmp/llvm-project-llvmorg-${llvm_version}"

declare -r zstd_tarball='/tmp/zstd.tar.gz'
declare -r zstd_directory='/tmp/zstd-dev'

declare -r zlib_tarball='/tmp/zlib.tar.gz'
declare -r zlib_directory='/tmp/zlib-develop'

declare -r install_prefix='/tmp/llvm-ld'

declare -r max_jobs='30'

declare -r host_triplet="${1}"

if ! [ -f "${zstd_tarball}" ]; then
	curl \
		--url 'https://github.com/facebook/zstd/archive/refs/heads/dev.tar.gz' \
		--retry '30' \
		--retry-all-errors \
		--retry-delay '0' \
		--retry-max-time '0' \
		--location \
		--silent \
		--output "${zstd_tarball}"
	
	tar \
		--directory="$(dirname "${zstd_directory}")" \
		--extract \
		--file="${zstd_tarball}"
fi

if ! [ -f "${zlib_tarball}" ]; then
	curl \
		--url 'https://github.com/madler/zlib/archive/refs/heads/develop.tar.gz' \
		--retry '30' \
		--retry-all-errors \
		--retry-delay '0' \
		--retry-max-time '0' \
		--location \
		--silent \
		--output "${zlib_tarball}"
	
	tar \
		--directory="$(dirname "${zlib_directory}")" \
		--extract \
		--file="${zlib_tarball}"
	
	sed \
		--in-place \
		's/(UNIX)/(1)/g; s/(NOT APPLE)/(0)/g' \
		"${zlib_directory}/CMakeLists.txt"
fi

if ! [ -f "${llvm_tarball}" ]; then
	curl \
		--url "https://github.com/llvm/llvm-project/archive/refs/tags/llvmorg-${llvm_version}.tar.gz" \
		--retry '30' \
		--retry-all-errors \
		--retry-delay '0' \
		--retry-max-time '0' \
		--location \
		--silent \
		--output "${llvm_tarball}"
	
	tar \
		--directory="$(dirname "${llvm_directory}")" \
		--extract \
		--file="${llvm_tarball}"
	
	patch --directory="${llvm_directory}" --strip='1' --input="${workdir}/submodules/termux-packages/packages/libllvm/llvm-tools-llvm-rtdyld-llvm-rtdyld.cpp.patch"
fi

[ -d "${llvm_directory}/tblgen-build" ] || mkdir "${llvm_directory}/tblgen-build"

cd "${llvm_directory}/tblgen-build"
rm --force --recursive ./*

CC= \
CXX= \
AR= \
AS= \
LD= \
NM= \
RANLIB= \
STRIP= \
OBJCOPY= \
READELF= \
cmake \
	-DCMAKE_BUILD_TYPE='MinSizeRel' \
	-DLLVM_ENABLE_PROJECTS='lld' \
	"${llvm_directory}/llvm"

cmake --build ./ --target 'llvm-min-tblgen' -- -j "${max_jobs}"

sudo ln --symbolic "$(realpath './bin/llvm-min-tblgen')" '/usr/bin/llvm-min-tblgen'

[ -d "${zstd_directory}/.build" ] || mkdir "${zstd_directory}/.build"

cd "${zstd_directory}/.build"
rm --force --recursive ./*

cmake \
	-S "${zstd_directory}/build/cmake" \
	-B "${PWD}" \
	-DCMAKE_TOOLCHAIN_FILE="/tmp/${host_triplet}.cmake" \
	-DCMAKE_C_FLAGS="-DZDICT_QSORT=ZDICT_QSORT_MIN" \
	-DCMAKE_INSTALL_PREFIX="${CROSS_COMPILE_SYSROOT}" \
	-DZSTD_BUILD_STATIC=ON \
	-DBUILD_SHARED_LIBS=ON \
	-DCMAKE_POSITION_INDEPENDENT_CODE=ON \
	-DCMAKE_PLATFORM_NO_VERSIONED_SONAME=ON \
	-DZSTD_BUILD_PROGRAMS=OFF \
	-DZSTD_BUILD_TESTS=OFF

cmake --build "${PWD}"
cmake --install "${PWD}" --strip

[ -d "${zlib_directory}/.build" ] || mkdir "${zlib_directory}/.build"

cd "${zlib_directory}/.build"
rm --force --recursive ./*

cmake \
	-S "${zlib_directory}" \
	-B "${PWD}" \
	-DCMAKE_TOOLCHAIN_FILE="/tmp/${host_triplet}.cmake" \
	-DCMAKE_INSTALL_PREFIX="${CROSS_COMPILE_SYSROOT}" \
	-DCMAKE_POSITION_INDEPENDENT_CODE=ON \
	-DCMAKE_PLATFORM_NO_VERSIONED_SONAME=ON

cmake --build "${PWD}"
cmake --install "${PWD}" --strip

[ -d "${llvm_directory}/build" ] || mkdir "${llvm_directory}/build"

cd "${llvm_directory}/build"
rm --force --recursive ./*

cmake \
	-DCMAKE_TOOLCHAIN_FILE="/tmp/${host_triplet}.cmake" \
	-DCMAKE_BUILD_TYPE='MinSizeRel' \
	-DCMAKE_CXX_FLAGS="-static-libstdc++ -static-libgcc" \
	-DCMAKE_INSTALL_PREFIX="${install_prefix}" \
	-DLLVM_HOST_TRIPLE="${host_triplet}" \
	-DLLVM_NATIVE_TOOL_DIR='/usr/bin' \
	-DLLVM_ENABLE_ASSERTIONS='OFF' \
	-DLLVM_INCLUDE_BENCHMARKS='OFF' \
	-DLLVM_INCLUDE_EXAMPLES='OFF' \
	-DLLVM_INCLUDE_TESTS='OFF' \
	-DLLVM_BUILD_DOCS='OFF' \
	-DLLVM_BUILD_LLVM_DYLIB='ON' \
	-DLLVM_ENABLE_LTO='OFF' \
	-DLLVM_ENABLE_PROJECTS='lld' \
	-DLLVM_ENABLE_ZLIB='FORCE_ON' \
	-DLLVM_ENABLE_ZSTD='FORCE_ON' \
	-DLLVM_TOOLCHAIN_TOOLS='llvm-ar;llvm-ranlib;llvm-objdump;llvm-rc;llvm-cvtres;llvm-nm;llvm-strings;llvm-readobj;llvm-dlltool;llvm-pdbutil;llvm-objcopy;llvm-strip;llvm-cov;llvm-profdata;llvm-addr2line;llvm-symbolizer;llvm-windres;llvm-ml;llvm-readelf;llvm-size;llvm-cxxfilt' \
	-Dzstd_LIBRARY="${CROSS_COMPILE_SYSROOT}/lib/libzstd.a" \
	-Dzstd_INCLUDE_DIR="${CROSS_COMPILE_SYSROOT}/include" \
	-DZLIB_LIBRARY="${CROSS_COMPILE_SYSROOT}/lib/libz.a" \
	-DZLIB_INCLUDE_DIR="${CROSS_COMPILE_SYSROOT}/include" \
	-DCMAKE_INSTALL_RPATH='$ORIGIN/../lib' \
	"${llvm_directory}/llvm"

cmake --build ./ -- -j '10'
cmake --install ./ --strip

rm --force --recursive ./*
