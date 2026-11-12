
#!/bin/bash

set -e

# ==========================================
# DATE / TIME
# ==========================================

SECONDS=0
DATE=$(date '+%Y%m%d-%H%M')

# ==========================================
# DEVICE
# ==========================================

DEVICE="${1:-chopin}"
DEFCONFIG="${DEVICE}_defconfig"
ZIPNAME="Kernel-${DEVICE}-${DATE}.zip"

echo "================================"
echo "Building kernel for: $DEVICE"
echo "================================"

# ==========================================
# TOOLCHAIN
# ==========================================

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

# ==========================================
# OPTIONS
# ==========================================

CLEAN_BUILD=false
INCLUDE_KSU=false

for arg in "$@"; do
    case "$arg" in
        -c)
            CLEAN_BUILD=true
            ;;
        -ksu)
            INCLUDE_KSU=true
            ZIPNAME="Kernel-SukiSU-${DEVICE}-${DATE}.zip"
            ;;
    esac
done

# ==========================================
# CLEAN BUILD
# ==========================================

if [ "$CLEAN_BUILD" = true ]; then
    echo "Cleaning build directory..."
    rm -rf out
fi

# ==========================================
# SUKISU INTEGRATION
# ==========================================

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

    # ======================================
    # STATIC_CALL DIAGNOSTIC
    # ======================================

    echo ""
    echo "========== SukiSU Compatibility Check =========="

    if [ -f drivers/kernelsu/kernel_includes.h ]; then

        echo "---- kernel_includes.h ----"

        sed -n '60,100p' \
        drivers/kernelsu/kernel_includes.h

    else
        echo "kernel_includes.h NOT FOUND"
    fi

    echo ""
    echo "---- static_call references ----"

    grep -RnE \
    '\b(static_call|DEFINE_STATIC_CALL|DECLARE_STATIC_CALL|static_call_update|static_call_cond)\b' \
    drivers/kernelsu \
    --include='*.c' \
    --include='*.h' || true

    echo "========== End Compatibility Check =========="
    echo ""

fi

# ==========================================
# PREPARE OUTPUT
# ==========================================

mkdir -p out

# ==========================================
# GENERATE DEFCONFIG
# ==========================================

echo "Generating defconfig..."

make O=out ARCH=arm64 "$DEFCONFIG"

# ==========================================
# VERIFY KSU CONFIGURATION
# ==========================================

if [ "$INCLUDE_KSU" = true ]; then

    echo "Checking SukiSU configuration..."

    if ! grep -q '^CONFIG_KSU=y' out/.config; then
        echo "ERROR: CONFIG_KSU is not enabled!"
        echo "Check your ${DEFCONFIG}"
        exit 1
    fi

    echo "CONFIG_KSU is enabled."

    echo ""
    echo "---- KSU CONFIGURATION ----"

    grep -E \
    '^CONFIG_KSU|^CONFIG_KPM|^CONFIG_KSU_SUSFS' \
    out/.config || true

fi

# ==========================================
# COMPILE KERNEL
# ==========================================

echo ""
echo "================================"
echo "Starting kernel compilation..."
echo "================================"

make -j"$(nproc --all)" \
    O=out \
    ARCH=arm64 \
    CC="ccache clang" \
    LLVM=1 \
    LLVM_IAS=1 \
    CROSS_COMPILE=aarch64-linux-gnu- \
    CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
    Image.gz

# ==========================================
# VERIFY KERNEL IMAGE
# ==========================================

if [ ! -f out/arch/arm64/boot/Image.gz ]; then
    echo "ERROR: Image.gz not found!"
    exit 1
fi

echo ""
echo "Kernel compiled successfully!"

# ==========================================
# ANYKERNEL3
# ==========================================

echo "Preparing AnyKernel3..."

if [ ! -d AnyKernel3 ]; then

    git clone -q --depth=1 \
        https://github.com/axl277/AnyKernel3 \
        AnyKernel3

fi

cp out/arch/arm64/boot/Image.gz AnyKernel3/

# ==========================================
# PACKAGE
# ==========================================

rm -f "$ZIPNAME"

(
    cd AnyKernel3

    zip -r9 "../$ZIPNAME" * \
        -x '*.git*' README.md '*placeholder'
)

# ==========================================
# FINISH
# ==========================================

echo ""
echo "================================"
echo "BUILD COMPLETED SUCCESSFULLY!"
echo "================================"

echo "Device: $DEVICE"
echo "SukiSU: $INCLUDE_KSU"
echo "KPM: Disabled"
echo "SUSFS: Not integrated"
echo "Zip: $ZIPNAME"

echo "Time: $((SECONDS / 60))m $((SECONDS % 60))s"

echo "================================"
