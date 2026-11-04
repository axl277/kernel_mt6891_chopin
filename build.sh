#!/bin/bash
#
# Build script for Xiaomi Chopin kernel
#

# Date/Time
SECONDS=0
DATE=$(date '+%Y%m%d-%H%M')

# Device
DEVICE="${1:-chopin}"
DEFCONFIG="${DEVICE}_defconfig"
ZIPNAME="Kernel-${DEVICE}-${DATE}.zip"

echo -e "Building for: $DEVICE\n"

# Ensure the toolchain is available
TC_DIR="$HOME/toolchains/proton-clang"
CURRENT_DIR=$(pwd)
if [ ! -d "$TC_DIR" ]; then
    mkdir -p "$HOME/toolchains"
    cd "$HOME/toolchains"
    git clone --depth=1 https://gitlab.com/LeCmnGend/proton-clang.git -b clang-15 proton-clang
    cd "$CURRENT_DIR"
fi

# Export environment variables secara global untuk sub-make (vDSO, scripts, dll.)
export PATH="$TC_DIR/bin:$PATH"
export ARCH=arm64
export SUBARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-
export CROSS_COMPILE_ARM32=arm-linux-gnueabi-
export CLANG_TRIPLE=aarch64-linux-gnu-

# Process options
CLEAN_BUILD=false
INCLUDE_KSU=false
for arg in "$@"; do
    case $arg in
        -c) CLEAN_BUILD=true ;;
        -ksu) INCLUDE_KSU=true
              ZIPNAME="Kernel-SukiSU-${DEVICE}-${DATE}.zip"
              ;;
    esac
done

[ "$CLEAN_BUILD" = true ] && rm -rf out

# SukiSU Integration
if [ "$INCLUDE_KSU" = true ]; then
    echo "Integrating SukiSU..."
    curl -LSs "https://raw.githubusercontent.com/SukiSU-Ultra/SukiSU-Ultra/main/kernel/setup.sh" | bash -s main
fi

# Definisi argumen Make secara terpusat
MAKE_ARGS=(
    O=out
    ARCH=arm64
    CC="ccache clang"
    LLVM=1
    LLVM_IAS=1
    CLANG_TRIPLE=aarch64-linux-gnu-
    CROSS_COMPILE=aarch64-linux-gnu-
    CROSS_COMPILE_ARM32=arm-linux-gnueabi-
)

# Compilation process
mkdir -p out
make "${MAKE_ARGS[@]}" $DEFCONFIG

echo -e "\nStarting compilation...\n"
if make -j$(nproc --all) "${MAKE_ARGS[@]}" Image.gz; then
    echo -e "\nKernel compiled successfully! Zipping up...\n"
    git clone -q --depth=1 https://github.com/axl277/AnyKernel3 AnyKernel3
    cp out/arch/arm64/boot/Image.gz AnyKernel3
    rm -rf *zip out/arch/arm64/boot
    (cd AnyKernel3 && zip -r9 "../$ZIPNAME" * -x '*.git*' README.md *placeholder)
    rm -rf AnyKernel3

    echo -e "\nCompleted in $((SECONDS / 60)) minute(s) and $((SECONDS % 60)) second(s)!"
    echo "Zip: $ZIPNAME"
else
    echo -e "\nCompilation failed!"
fi
