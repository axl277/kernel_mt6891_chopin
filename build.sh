
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
DEFCONFIG_PATH="arch/arm64/configs/${DEFCONFIG}"
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
# CHECK DEFCONFIG
# ==========================================

if [ ! -f "$DEFCONFIG_PATH" ]; then
    echo "ERROR: Defconfig not found!"
    echo "$DEFCONFIG_PATH"
    exit 1
fi

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
    echo "Branch: main"
    echo "================================"

    if [ ! -d drivers/kernelsu ]; then

        curl -LSs \
        "https://raw.githubusercontent.com/SukiSU-Ultra/SukiSU-Ultra/main/kernel/setup.sh" \
        | bash -s main

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
    echo "========== STATIC_CALL CHECK =========="

    if [ -f drivers/kernelsu/hook/lsm_hook.c ]; then
        echo "---- lsm_hook.c ----"
        sed -n '1,100p' drivers/kernelsu/hook/lsm_hook.c
    fi

    echo ""
    echo "---- static_call references ----"

    grep -RnE \
    'static_call|DEFINE_STATIC_CALL|DECLARE_STATIC_CALL|static_call_update|static_call_cond' \
    drivers/kernelsu \
    --include='*.c' \
    --include='*.h' || true

    echo "========== END CHECK =========="

    # ======================================
    # FIX KSU DEFCONFIG
    # ======================================

    echo ""
    echo "Preparing SukiSU configuration..."

    set_config() {
        local CONFIG_NAME="$1"

        if grep -q "^${CONFIG_NAME}=.*" "$DEFCONFIG_PATH"; then
            sed -i "s/^${CONFIG_NAME}=.*/${CONFIG_NAME}=y/" "$DEFCONFIG_PATH"

        elif grep -q "^# ${CONFIG_NAME} is not set" "$DEFCONFIG_PATH"; then
            sed -i "s/^# ${CONFIG_NAME} is not set/${CONFIG_NAME}=y/" "$DEFCONFIG_PATH"

        else
            echo "${CONFIG_NAME}=y" >> "$DEFCONFIG_PATH"
        fi
    }

    set_config CONFIG_KPROBES
    set_config CONFIG_EXT4_FS
    set_config CONFIG_KSU

    echo "Required configuration added:"
    echo "CONFIG_KPROBES=y"
    echo "CONFIG_EXT4_FS=y"
    echo "CONFIG_KSU=y"

fi

# ==========================================
# PREPARE OUTPUT
# ==========================================

mkdir -p out

# ==========================================
# GENERATE DEFCONFIG
# ==========================================

echo ""
echo "Generating defconfig..."

make O=out ARCH=arm64 "$DEFCONFIG"

# ==========================================
# VERIFY KSU CONFIGURATION
# ==========================================

if [ "$INCLUDE_KSU" = true ]; then

    echo ""
    echo "========== KSU CONFIGURATION =========="

    grep -E \
    '^(CONFIG_KSU|CONFIG_KPROBES|CONFIG_KRETPROBES|CONFIG_EXT4_FS|CONFIG_KPM|CONFIG_KSU_SUSFS)=' \
    out/.config || true

    echo "======================================="

    if ! grep -q '^CONFIG_KPROBES=y' out/.config; then
        echo "ERROR: CONFIG_KPROBES is not enabled!"
        exit 1
    fi

    if ! grep -q '^CONFIG_EXT4_FS=y' out/.config; then
        echo "ERROR: CONFIG_EXT4_FS is not enabled!"
        exit 1
    fi

    if ! grep -q '^CONFIG_KSU=y' out/.config; then
        echo "ERROR: CONFIG_KSU is not enabled!"
        echo "Kconfig rejected CONFIG_KSU."
        echo "Check KSU dependencies and Kconfig integration."
        exit 1
    fi

    echo "SukiSU configuration verified."

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
echo "Integration: main"
echo "KPM: Disabled"
echo "SUSFS: Not integrated"
echo "Zip: $ZIPNAME"

echo "Time: $((SECONDS / 60))m $((SECONDS % 60))s"

echo "================================"
