
#!/bin/bash

set -euo pipefail

# Date / Time
SECONDS=0
DATE=$(date '+%Y%m%d-%H%M')

# Device
DEVICE="chopin"
CLEAN_BUILD=false
INCLUDE_KSU=false

# MultiManager identity
DRIVER_NAME_FORMAT="%TAG_NAME%-%COMMIT_SHA%@MultiManager"

# Process options
for arg in "$@"; do
    case "$arg" in
        -c)
            CLEAN_BUILD=true
            ;;
        -ksu)
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
    ZIPNAME="Kernel-MultiManager-${DEVICE}-${DATE}.zip"
else
    ZIPNAME="Kernel-${DEVICE}-${DATE}.zip"
fi

ROOT_DIR=$(pwd -P)

echo "Building for: $DEVICE"
echo "Defconfig: $DEFCONFIG"

# Toolchain
TC_DIR="$HOME/toolchains/proton-clang"

if [ ! -d "$TC_DIR" ]; then
    mkdir -p "$HOME/toolchains"
    git clone --depth=1 \
        -b clang-15 \
        https://gitlab.com/LeCmnGend/proton-clang.git \
        "$TC_DIR"
fi

export PATH="$TC_DIR/bin:$PATH"

# Clean build
if [ "$CLEAN_BUILD" = true ]; then
    echo "Cleaning build directory..."
    rm -rf out
fi

# BakaSU integration
if [ "$INCLUDE_KSU" = true ]; then

    echo "Integrating BakaSU..."

    curl -fsSL \
        "https://raw.githubusercontent.com/Baka-SU/BakaSU/main/kernel/setup.sh" \
        | bash

    echo "BakaSU integration completed."

fi

# Create output directory
mkdir -p out

# Generate defconfig
echo "Generating defconfig..."

make O=out ARCH=arm64 "$DEFCONFIG"

# MultiManager driver identity
if [ "$INCLUDE_KSU" = true ]; then

    echo "Configuring MultiManager identity..."

    if [ ! -f "out/.config" ]; then
        echo "ERROR: out/.config not found!"
        exit 1
    fi

    if [ ! -f "scripts/config" ]; then
        echo "ERROR: scripts/config not found!"
        exit 1
    fi

    # Enable BakaSU
    bash scripts/config \
        --file out/.config \
        --enable KSU

    # Set custom driver version name
    bash scripts/config \
        --file out/.config \
        --set-str KSU_FULL_NAME_FORMAT "$DRIVER_NAME_FORMAT"

    # Apply configuration
    make O=out ARCH=arm64 olddefconfig

    echo ""
    echo "========== MULTIMANAGER CONFIG =========="

    grep -E 'CONFIG_KSU=|CONFIG_KSU_FULL_NAME_FORMAT=' out/.config

    echo "========================================="

fi

# Compilation
echo ""
echo "Starting compilation..."
echo ""

if make -j"$(nproc --all)" \
    O=out \
    ARCH=arm64 \
    CC="ccache clang" \
    LLVM=1 \
    LLVM_IAS=1 \
    CROSS_COMPILE=aarch64-linux-gnu- \
    CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
    Image.gz
then

    echo ""
    echo "Kernel compiled successfully!"
    echo "Preparing AnyKernel3..."

    rm -rf AnyKernel3

    git clone -q --depth=1 \
        https://github.com/axl277/AnyKernel3 \
        AnyKernel3

    cp out/arch/arm64/boot/Image.gz AnyKernel3/

    rm -f ./*.zip

    (
        cd AnyKernel3
        zip -r9 "../$ZIPNAME" * \
            -x '*.git*' README.md '*placeholder'
    )

    rm -rf AnyKernel3
    rm -rf out/arch/arm64/boot

    echo ""
    echo "Build completed successfully!"
    echo "Device: $DEVICE"
    echo "Driver: MultiManager"
    echo "Zip: $ZIPNAME"
    echo "Completed in $((SECONDS / 60)) minute(s) and $((SECONDS % 60)) second(s)!"

else

    echo ""
    echo "Kernel compilation failed!"
    exit 1

fi
