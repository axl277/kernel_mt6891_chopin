#!/bin/bash

set -e

# Date / Time
SECONDS=0
DATE=$(date '+%Y%m%d-%H%M')

# Default Options
DEVICE="chopin"
CLEAN_BUILD=false
INCLUDE_KSU=false

# Parse Arguments
for arg in "$@"; do
    case "$arg" in
        -c|--clean)
            CLEAN_BUILD=true
            ;;
        -ksu|--ksu)
            INCLUDE_KSU=true
            ;;
        -*)
            echo "Unknown option: $arg"
            exit 1
            ;;
        *)
            DEVICE="$arg"
            ;;
    esac
done

DEFCONFIG="${DEVICE}_defconfig"
if [ "$INCLUDE_KSU" = true ]; then
    ZIPNAME="Kernel-SukiSU-${DEVICE}-${DATE}.zip"
else
    ZIPNAME="Kernel-${DEVICE}-${DATE}.zip"
fi

echo -e "Building for: $DEVICE (SukiSU: $INCLUDE_KSU)\n"

# Toolchain
TC_DIR="$HOME/toolchains/proton-clang"
CURRENT_DIR=$(pwd)

if [ ! -d "$TC_DIR" ]; then
    mkdir -p "$HOME/toolchains"
    cd "$HOME/toolchains"
    git clone --depth=1 \
        https://gitlab.com/LeCmnGend/proton-clang.git \
        -b clang-15 proton-clang
    cd "$CURRENT_DIR"
fi

export PATH="$TC_DIR/bin:$PATH"

# Clean build
if [ "$CLEAN_BUILD" = true ]; then
    echo "Cleaning build directory..."
    rm -rf out
fi

# SukiSU Integration
if [ "$INCLUDE_KSU" = true ]; then

    echo "================================"
    echo "Integrating SukiSU-Ultra"
    echo "Branch: nongki (Kernel 4.14)"
    echo "================================"

    if [ ! -d drivers/kernelsu ]; then
        curl -LSs \
        "https://raw.githubusercontent.com/SukiSU-Ultra/SukiSU-Ultra/nongki/kernel/setup.sh" \
        | bash -s nongki
    else
        echo "SukiSU source already exists."
    fi

    # Verify source
    if [ ! -d drivers/kernelsu ]; then
        echo "ERROR: SukiSU source not found!"
        exit 1
    fi

    # Verify Kconfig
    if ! grep -q 'kernelsu/Kconfig' drivers/Kconfig; then
        echo "ERROR: SukiSU Kconfig integration missing!"
        exit 1
    fi

    # Verify Makefile
    if ! grep -q 'kernelsu/' drivers/Makefile; then
        echo "ERROR: SukiSU Makefile integration missing!"
        exit 1
    fi

    echo "SukiSU source integration verified."

fi

# Prepare output
mkdir -p out

# Generate defconfig
echo "Generating defconfig..."
make O=out ARCH=arm64 "$DEFCONFIG"

# Configure SukiSU options dynamically
if [ "$INCLUDE_KSU" = true ]; then
    echo "Enabling SukiSU Manual Hook in .config..."
    ./scripts/config --file out/.config \
        -e CONFIG_KSU \
        -e CONFIG_KSU_MANUAL_HOOK \
        -d CONFIG_KSU_KPROBES_HOOK

    make O=out ARCH=arm64 olddefconfig

    if ! grep -q '^CONFIG_KSU=y' out/.config; then
        echo "ERROR: CONFIG_KSU failed to enable!"
        exit 1
    fi

    grep -E '^CONFIG_KSU|^CONFIG_KPM' out/.config || true
fi

# Compile
echo -e "\nStarting compilation...\n"

make -j"$(nproc --all)" \
    O=out \
    ARCH=arm64 \
    CC="ccache clang" \
    LLVM=1 \
    LLVM_IAS=1 \
    CROSS_COMPILE=aarch64-linux-gnu- \
    CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
    Image.gz

# Verify kernel image
if [ ! -f out/arch/arm64/boot/Image.gz ]; then
    echo "ERROR: Image.gz not found!"
    exit 1
fi

echo -e "\nKernel compiled successfully!"

# AnyKernel3
echo "Preparing AnyKernel3..."

if [ ! -d AnyKernel3 ]; then
    git clone -q --depth=1 \
        https://github.com/axl277/AnyKernel3 \
        AnyKernel3
fi

cp out/arch/arm64/boot/Image.gz AnyKernel3/

# Package
rm -f "$ZIPNAME"

(
    cd AnyKernel3
    zip -r9 "../$ZIPNAME" * \
        -x '*.git*' README.md '*placeholder'
)

# Finish
echo -e "\n================================"
echo "Build completed successfully!"
echo "Device: $DEVICE"
echo "SukiSU: $INCLUDE_KSU"
echo "Zip: $ZIPNAME"
echo "Time: $((SECONDS / 60))m $((SECONDS % 60))s"
echo "================================"
