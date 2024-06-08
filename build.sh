#!/bin/bash

set -eu

declare -r workdir="${PWD}"

declare -r llvm_version='18.1.7'

declare -r llvm_tarball='/tmp/llvm.tar.gz'
declare -r llvm_directory="/tmp/llvm-project-llvmorg-${llvm_version}"

declare -r install_prefix='/tmp/llvm-ld'

declare -r max_jobs="$(($(nproc) * 17))"

declare -r host_triplet="${1}"

source "./submodules/obggcc/toolchains/${host_triplet}.sh"

if ! [ -f "${llvm_tarball}" ]; then
	wget --no-verbose "https://github.com/llvm/llvm-project/archive/refs/tags/llvmorg-${llvm_version}.tar.gz" --output-document="${llvm_tarball}"
	tar --directory="$(dirname "${llvm_directory}")" --extract --file="${llvm_tarball}"
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

[ -d "${llvm_directory}/build" ] || mkdir "${llvm_directory}/build"

cd "${llvm_directory}/build"
rm --force --recursive ./*

cmake \
	-DCMAKE_TOOLCHAIN_FILE="${workdir}/submodules/obggcc/toolchains/${host_triplet}.cmake" \
	-DCMAKE_BUILD_TYPE='MinSizeRel' \
	-DCMAKE_CXX_FLAGS='-static-libgcc -static-libstdc++' \
	-DCMAKE_INSTALL_PREFIX="${install_prefix}" \
	-DLLVM_HOST_TRIPLE="${host_triplet}" \
	-DLLVM_NATIVE_TOOL_DIR='/usr/bin' \
	-DLLVM_ENABLE_ASSERTIONS='OFF' \
	-DLLVM_INCLUDE_BENCHMARKS='OFF' \
	-DLLVM_INCLUDE_EXAMPLES='OFF' \
	-DLLVM_INCLUDE_TESTS='OFF' \
	-DLLVM_BUILD_DOCS='OFF' \
	-DLLVM_BUILD_LLVM_DYLIB='ON' \
	-DLLVM_ENABLE_PROJECTS='lld' \
	-DLLVM_TOOLCHAIN_TOOLS='llvm-ar;llvm-ranlib;llvm-objdump;llvm-rc;llvm-cvtres;llvm-nm;llvm-strings;llvm-readobj;llvm-dlltool;llvm-pdbutil;llvm-objcopy;llvm-strip;llvm-cov;llvm-profdata;llvm-addr2line;llvm-symbolizer;llvm-windres;llvm-ml;llvm-readelf;llvm-size;llvm-cxxfilt' \
	"${llvm_directory}/llvm"

cmake --build ./ -- -j $((max_jobs / 3))
cmake --install ./ --strip

rm --force --recursive ./*
