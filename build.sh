
#!/bin/bash

set -e

# Date / Time
SECONDS=0
DATE=$(date '+%Y%m%d-%H%M')

# Device
DEVICE="${1:-chopin}"
DEFCONFIG="${DEVICE}_defconfig"
ZIPNAME="Kernel-${DEVICE}-${DATE}.zip"

echo -e "Building for: $DEVICE\n"

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

# Options
CLEAN_BUILD=false
INCLUDE_KSU=false

for arg in "$@"; do
    case "$arg" in
        -c)
            CLEAN_BUILD=true
            ;;
        -ksu)
            INCLUDE_KSU=true
            ZIPNAME="Kernel-SuSU-${DEVICE}-${DATE}.zip"
            ;;
    esac
done

# Clean build
if [ "$CLEAN_BUILD" = true ]; then
    echo "Cleaning build directory..."
    rm -rf out
fi

# SukiSU Integration
if [ "$INCLUDE_KSU" = true ]; then

    echo "================================"
    echo "Integrating SukiSU-Ultra"
    echo "Branch: builtin"
    echo "================================"

    if [ ! -d drivers/kernelsu ]; then

        curl -LSs \
        "https://raw.githubusercontent.com/SukiSU-Ultra/SukiSU-Ultra/main/kernel/setup.sh" \
        | bash -s builtin

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

# Verify KSU configuration
if [ "$INCLUDE_KSU" = true ]; then

    echo "Checking SukiSU configuration..."

    if ! grep -q '^CONFIG_KSU=y' out/.config; then
        echo "ERROR: CONFIG_KSU is not enabled!"
        echo "Check your ${DEFCONFIG}"
        exit 1
    fi

    echo "CONFIG_KSU is enabled."

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
