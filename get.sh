#!/system/bin/sh
# get_device_info.sh - Collect device info for AnyKernel3
# Run as root: su -c "sh get_device_info.sh"
# Output: <script_dir>/<device_codename>.json + .log

# POSIX compliant - works with mksh, bash, dash, busybox sh
set -e

# ============================================
# DETECT SCRIPT LOCATION & SETUP BIN PATH
# ============================================
SCRIPT_PATH="$0"
SCRIPT_DIR=$(dirname "$SCRIPT_PATH")
SCRIPT_DIR=$(cd "$SCRIPT_DIR" && pwd)
BIN_DIR="$SCRIPT_DIR/bin"
export PATH="$BIN_DIR:$PATH"

# ============================================
# CONFIGURATION
# ============================================
VERBOSE=1
TMP_DIR="/data/local/tmp/device_info_$$"

# ============================================
# COLORS
# ============================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ============================================
# LOGGING FUNCTIONS
# ============================================
log_header() {
    msg="${BLUE}=== $1 ===${NC}"
    echo "$msg"
    echo "$msg" >> "$LOG_FILE"
}
log_info() {
    msg="${GREEN}[INFO]${NC} $1"
    echo "$msg"
    echo "$msg" >> "$LOG_FILE"
}
log_warn() {
    msg="${YELLOW}[WARN]${NC} $1"
    echo "$msg"
    echo "$msg" >> "$LOG_FILE"
}
log_error() {
    msg="${RED}[ERROR]${NC} $1"
    echo "$msg"
    echo "$msg" >> "$LOG_FILE"
}
log_cmd() {
    [ $VERBOSE -eq 1 ] && {
        msg="${CYAN}[RUNNING]${NC} $1"
        echo "$msg"
        echo "$msg" >> "$LOG_FILE"
    }
}
log_step() {
    msg="${BLUE}[STEP]${NC} $1"
    echo "$msg"
    echo "$msg" >> "$LOG_FILE"
}
log_raw() {
    echo "$1"
    echo "$1" >> "$LOG_FILE"
}

# JSON helpers
json_init() { echo "{" > "$JSON_FILE"; }
json_add()  { printf '  "%s": %s,\n' "$1" "$2" >> "$JSON_FILE"; }
json_add_str() { printf '  "%s": "%s",\n' "$1" "$2" >> "$JSON_FILE"; }
json_finalize() { sed -i '$ s/,$//' "$JSON_FILE"; echo "}" >> "$JSON_FILE"; }

# Escape for JSON
json_escape() { echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\n/\\n/g; s/\r/\\r/g; s/\t/\\t/g'; }

# Run command with logging - output goes to stdout and log file
run_cmd() {
    log_cmd "$*"
    "$@" 2>&1 | tee -a "$LOG_FILE"
}

# Getprop with fallback
get_prop() {
    getprop "$1" 2>/dev/null || echo "N/A"
}

# ============================================
# ROOT CHECK
# ============================================
if [ "$(id -u)" -ne 0 ]; then
    log_error "Script ini memerlukan root access. Jalankan: su -c \"sh $0\""
    exit 1
fi

# ============================================
# INIT OUTPUT FILES
# ============================================
mkdir -p "$TMP_DIR"

DEVICE_CODENAME=$(get_prop ro.product.device)
BUILD_PRODUCT=$(get_prop ro.build.product)
VENDOR_DEVICE=$(get_prop ro.product.vendor.device)

OUT_BASE="${SCRIPT_DIR}/${DEVICE_CODENAME}"
JSON_FILE="${OUT_BASE}.json"
LOG_FILE="${OUT_BASE}.log"

echo "Device Info Collector for AnyKernel3" > "$LOG_FILE"
echo "Device: $DEVICE_CODENAME" >> "$LOG_FILE"
echo "Started: $(date)" >> "$LOG_FILE"
echo "Temp dir: $TMP_DIR" >> "$LOG_FILE"
echo "JSON output: $JSON_FILE" >> "$LOG_FILE"
echo "Log output: $LOG_FILE" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"

echo "=========================================="
echo "  Device Info Collector for AnyKernel3"
echo "  Device: $DEVICE_CODENAME"
echo "  Started: $(date)"
echo "  Temp dir: $TMP_DIR"
echo "  JSON output: $JSON_FILE"
echo "  Log output: $LOG_FILE"
echo "=========================================="
echo ""

json_init

# ============================================
# 1. BASIC DEVICE INFO
# ============================================
log_header "1. BASIC DEVICE INFO"

MODEL=$(get_prop ro.product.model)
BRAND=$(get_prop ro.product.brand)
MANUFACTURER=$(get_prop ro.product.manufacturer)
HARDWARE=$(get_prop ro.hardware)
BOARD=$(get_prop ro.board.platform)

log_info "ro.product.device        : $DEVICE_CODENAME"
log_info "ro.build.product         : $BUILD_PRODUCT"
log_info "ro.product.vendor.device : $VENDOR_DEVICE"
log_info "ro.product.model         : $MODEL"
log_info "ro.product.brand         : $BRAND"
log_info "ro.product.manufacturer  : $MANUFACTURER"
log_info "ro.hardware              : $HARDWARE"
log_info "ro.board.platform        : $BOARD"

# Determine all codenames for AnyKernel
AK_CODENAMES="$DEVICE_CODENAME"
[ "$BUILD_PRODUCT" != "$DEVICE_CODENAME" ] && [ "$BUILD_PRODUCT" != "N/A" ] && AK_CODENAMES="$AK_CODENAMES $BUILD_PRODUCT"
[ "$VENDOR_DEVICE" != "$DEVICE_CODENAME" ] && [ "$VENDOR_DEVICE" != "N/A" ] && AK_CODENAMES="$AK_CODENAMES $VENDOR_DEVICE"
AK_CODENAMES=$(echo "$AK_CODENAMES" | tr ' ' '\n' | sort -u | tr '\n' ',' | sed 's/,$//')

log_info "AnyKernel device.names: $AK_CODENAMES"

json_add_str "device_codename" "$DEVICE_CODENAME"
json_add_str "build_product" "$BUILD_PRODUCT"
json_add_str "vendor_device" "$VENDOR_DEVICE"
json_add_str "model" "$MODEL"
json_add_str "brand" "$BRAND"
json_add_str "manufacturer" "$MANUFACTURER"
json_add_str "hardware" "$HARDWARE"
json_add_str "board_platform" "$BOARD"
json_add_str "anykernel_codenames" "$AK_CODENAMES"

# ============================================
# 2. ANDROID VERSION & PATCH
# ============================================
log_header "2. ANDROID VERSION & SECURITY PATCH"

ANDROID_VER=$(get_prop ro.build.version.release)
ANDROID_SDK=$(get_prop ro.build.version.sdk)
SECURITY_PATCH=$(get_prop ro.build.version.security_patch)
VENDOR_PATCH=$(get_prop ro.vendor.build.security_patch 2>/dev/null || get_prop ro.boot.vendor.patch.level 2>/dev/null || echo "N/A")
DISPLAY_ID=$(get_prop ro.build.display.id 2>/dev/null || echo "N/A")
BUILD_FINGERPRINT=$(get_prop ro.build.fingerprint 2>/dev/null || echo "N/A")

log_info "Android version: $ANDROID_VER (SDK $ANDROID_SDK)"
log_info "Security patch: $SECURITY_PATCH"
log_info "Vendor patch: $VENDOR_PATCH"
log_info "Build display: $DISPLAY_ID"
log_info "Build fingerprint: $BUILD_FINGERPRINT"

json_add_str "android_version" "$ANDROID_VER"
json_add_str "android_sdk" "$ANDROID_SDK"
json_add_str "security_patch" "$SECURITY_PATCH"
json_add_str "vendor_security_patch" "$VENDOR_PATCH"
json_add_str "build_display_id" "$DISPLAY_ID"
json_add_str "build_fingerprint" "$BUILD_FINGERPRINT"

# ============================================
# 3. ARCHITECTURE & CPU
# ============================================
log_header "3. ARCHITECTURE & CPU"

CPU_ABI=$(get_prop ro.product.cpu.abi)
CPU_ABI2=$(get_prop ro.product.cpu.abi2)
CPU_ABI_LIST=$(get_prop ro.product.cpu.abilist)
KERNEL_ARCH=$(uname -m)
KERNEL_VER=$(uname -r)

log_info "CPU ABI: $CPU_ABI"
log_info "CPU ABI2: $CPU_ABI2"
log_info "CPU ABI List: $CPU_ABI_LIST"
log_info "Kernel arch: $KERNEL_ARCH"
log_info "Kernel version: $KERNEL_VER"

json_add_str "cpu_abi" "$CPU_ABI"
json_add_str "cpu_abi2" "$CPU_ABI2"
json_add_str "cpu_abi_list" "$CPU_ABI_LIST"
json_add_str "kernel_arch" "$KERNEL_ARCH"
json_add_str "kernel_version" "$KERNEL_VER"

# ============================================
# 4. SLOT A/B & PARTITIONS
# ============================================
log_header "4. SLOT A/B & PARTITION INFO"

SLOT_SUFFIX=$(get_prop ro.boot.slot_suffix)
SLOT=$(get_prop ro.boot.slot)

log_info "ro.boot.slot_suffix: $SLOT_SUFFIX"
log_info "ro.boot.slot: $SLOT"

IS_AB=0
ACTIVE_SLOT=""
if [ -n "$SLOT_SUFFIX" ] && [ "$SLOT_SUFFIX" != "N/A" ]; then
    IS_AB=1
    ACTIVE_SLOT="$SLOT_SUFFIX"
    log_info "Device is A/B (slot: $SLOT_SUFFIX)"
elif [ -n "$SLOT" ] && [ "$SLOT" != "N/A" ]; then
    IS_AB=1
    ACTIVE_SLOT="_$SLOT"
    log_info "Device is A/B (slot: _$SLOT)"
else
    if ls /dev/block/by-name/boot_a 2>/dev/null | grep -q .; then
        IS_AB=1
        log_info "Device is A/B (detected via partition)"
    else
        log_info "Device is Non-A/B"
    fi
fi

json_add_str "is_ab_device" "$IS_AB"
json_add_str "active_slot" "$ACTIVE_SLOT"
json_add_str "slot_suffix" "$SLOT_SUFFIX"

# Partition scan
log_step "Scanning partitions..."
PARTITIONS_JSON=""
for part in boot dtbo vendor_boot init_boot vendor_kernel_boot recovery dtb vbmeta vbmeta_system vbmeta_vendor super; do
    for suffix in "" "_a" "_b"; do
        path="/dev/block/by-name/${part}${suffix}"
        if [ -e "$path" ] || [ -L "$path" ]; then
            target=$(readlink -f "$path" 2>/dev/null || echo "$path")
            size=$(blockdev --getsize64 "$target" 2>/dev/null || echo "0")
            size_mb=$((size / 1024 / 1024))
            log_info "  ${part}${suffix} -> $target (${size_mb} MB)"
            PARTITIONS_JSON="${PARTITIONS_JSON}{\"name\":\"${part}${suffix}\",\"path\":\"${target}\",\"size_mb\":${size_mb}},"
        fi
    done
done

# Platform paths
find /dev/block/platform -name "boot*" -o -name "dtbo*" -o -name "vendor_boot*" -o -name "init_boot*" -o -name "recovery*" 2>/dev/null | while read p; do
    size=$(blockdev --getsize64 "$p" 2>/dev/null || echo "0")
    size_mb=$((size / 1024 / 1024))
    log_info "  $p (${size_mb} MB)"
    PARTITIONS_JSON="${PARTITIONS_JSON}{\"name\":\"$(basename "$p")\",\"path\":\"${p}\",\"size_mb\":${size_mb}},"
done

PARTITIONS_JSON="[${PARTITIONS_JSON%,}]"
json_add "partitions" "$PARTITIONS_JSON"

# ============================================
# 5. BOOT IMAGE HEADER ANALYSIS
# ============================================
log_header "5. BOOT IMAGE HEADER ANALYSIS"

BOOT_IMG="/dev/block/by-name/boot"
[ "$IS_AB" -eq 1 ] && [ -n "$SLOT_SUFFIX" ] && BOOT_IMG="/dev/block/by-name/boot$SLOT_SUFFIX"

BOOT_HEADER_JSON="{}"
HDR_VER="unknown"
if [ -e "$BOOT_IMG" ]; then
    log_info "Analyzing boot image: $BOOT_IMG"
    TMP_BOOT="$TMP_DIR/boot_header.img"
    run_cmd dd if="$BOOT_IMG" of="$TMP_BOOT" bs=4096 count=1

    # Manual parse sebelum magiskboot agar HDR_VER tersedia untuk fallback
    MAGIC=$(dd if="$TMP_BOOT" bs=1 count=8 2>/dev/null | od -An -tx1 | tr -d ' \n' || echo "")
    HDR_VER="unknown"
    if [ "$MAGIC" = "414e44524f494421" ]; then
        HDR_VER=$(dd if="$TMP_BOOT" bs=1 skip=24 count=4 2>/dev/null | od -An -tu4 | tr -d ' \n' || echo "unknown")
        log_info "Boot header v0-v3 detected, version: $HDR_VER"
    elif dd if="$TMP_BOOT" bs=1 count=4 skip=0 2>/dev/null | grep -q "ELF"; then
        HDR_VER="4+ (ELF)"
        log_info "ELF format detected (header v4+)"
    else
        log_warn "Unknown boot image format"
    fi

    if [ -x "$BIN_DIR/magiskboot" ]; then
        log_step "Running magiskboot unpack -h"
        MB_OUT_FILE="$TMP_DIR/mb_header_out.txt"
        (
            "$BIN_DIR/magiskboot" unpack -h "$TMP_BOOT" 2>&1
        ) | tee "$MB_OUT_FILE"
        MB_OUT=$(cat "$MB_OUT_FILE" 2>/dev/null)
        echo "$MB_OUT" | head -30 | while IFS= read -r line; do
            log_raw "$line"
        done
        BOOT_HEADER_JSON=$(echo "$MB_OUT" | grep -E '^[A-Z_]+=' | sed 's/\([^=]*\)=\(.*\)/"\1":"\2"/' | paste -sd, | sed 's/^/{/;s/$/}/')
        # Fallback: jika magiskboot lapor corrupt tapi manual valid, isi manual
        if [ -z "$BOOT_HEADER_JSON" ] || echo "$MB_OUT" | grep -q "Corrupted"; then
            MANUAL_HDR="{"
            MANUAL_HDR="$MANUAL_HDR\"magic\":\"ANDROID!\","
            MANUAL_HDR="$MANUAL_HDR\"header_version\":\"$HDR_VER\""
            MANUAL_HDR="$MANUAL_HDR}"
            BOOT_HEADER_JSON="$MANUAL_HDR"
            log_info "Fallback to manual header parsing (magiskboot may report corrupt)"
        fi
        rm -f "$MB_OUT_FILE"
    fi

    rm -f "$TMP_BOOT"
else
    log_error "Boot partition not found at $BOOT_IMG"
fi

json_add "boot_header" "$BOOT_HEADER_JSON"
json_add_str "boot_header_version" "$HDR_VER"
json_add_str "boot_partition" "$BOOT_IMG"

# ============================================
# 6. RAMDISK COMPRESSION
# ============================================
log_header "6. RAMDISK COMPRESSION DETECTION"

RAMDISK_COMP="unknown"
RAMDISK_SIZE=0

TMP_BOOT="$TMP_DIR/boot_ramdisk.img"
run_cmd dd if="$BOOT_IMG" of="$TMP_BOOT"

if [ -x "$BIN_DIR/magiskboot" ]; then
    log_step "Unpacking boot image with magiskboot"
    MB_OUT_FILE="$TMP_DIR/mb_unpack_out.txt"
    (
        cd "$TMP_DIR" || exit 1
        "$BIN_DIR/magiskboot" unpack "$TMP_BOOT" 2>&1
    ) | tee "$MB_OUT_FILE" || log_warn "magiskboot unpack failed (section 6)"
    rm -f "$MB_OUT_FILE"
    for f in "$TMP_DIR"/ramdisk.cpio*; do
        [ -f "$f" ] && RAMDISK_SIZE=$(wc -c < "$f") && case "$f" in
            *.gz)  RAMDISK_COMP="gzip" ;;
            *.lz4) RAMDISK_COMP="lz4" ;;
            *.lzo) RAMDISK_COMP="lzop" ;;
            *.bz2) RAMDISK_COMP="bzip2" ;;
            *.xz)  RAMDISK_COMP="xz" ;;
            *.zst) RAMDISK_COMP="zstd" ;;
            *)     RAMDISK_COMP="none" ;;
        esac
    done
    rm -f "$TMP_DIR"/ramdisk.cpio* "$TMP_DIR"/kernel* "$TMP_DIR"/dt* "$TMP_DIR"/cmdline.txt "$TMP_DIR"/header 2>/dev/null
else
    # Fallback: detect from boot image header directly
    case "$(dd if="$TMP_BOOT" bs=1 count=8 2>/dev/null | od -An -tx1 | tr -d ' \n')" in
        1f8b08) RAMDISK_COMP="gzip" ;;
        02214c18) RAMDISK_COMP="lz4" ;;
        894c5a4f) RAMDISK_COMP="lzop" ;;
        425a6839) RAMDISK_COMP="bzip2" ;;
        fdfb6b6a) RAMDISK_COMP="xz" ;;
        28b52ffd) RAMDISK_COMP="zstd" ;;
    esac
    RAMDISK_SIZE=$(wc -c < "$TMP_BOOT")
fi

log_info "Ramdisk compression: $RAMDISK_COMP"
log_info "Ramdisk size: $RAMDISK_SIZE bytes ($((RAMDISK_SIZE/1024)) KB)"

json_add_str "ramdisk_compression" "$RAMDISK_COMP"
json_add_str "ramdisk_size_bytes" "$RAMDISK_SIZE"

# Fallback: jika boot ramdisk kosong (RAMDISK_SZ 0 atau size 0), cek vendor_boot / init_boot
if [ "$RAMDISK_SIZE" -eq 0 ] || [ "$RAMDISK_COMP" = "unknown" ]; then
    for vb in "/dev/block/by-name/vendor_boot" "/dev/block/by-name/init_boot"; do
        [ -e "$vb" ] || continue
        log_info "Checking ramdisk in $vb (boot ramdisk was empty)"
        TMP_VB_CHECK="$TMP_DIR/check_vb.img"
        run_cmd dd if="$vb" of="$TMP_VB_CHECK" bs=4096 count=1 2>/dev/null || true
        MAGIC_VB=$(dd if="$TMP_VB_CHECK" bs=1 count=8 2>/dev/null | od -An -tx1 | tr -d ' \n' || echo "")
        [ -n "$MAGIC_VB" ] && log_info "  $vb magic: $MAGIC_VB"
        # Coba unpack dengan magiskboot jika ada
        if [ -x "$BIN_DIR/magiskboot" ]; then
            VB_UNPACK="$TMP_DIR/vb_unpack"
            mkdir -p "$VB_UNPACK"
            ("$BIN_DIR/magiskboot" unpack "$vb" 2>/dev/null) || true
            # Deteksi file ramdisk dari unpack
            for f in "$VB_UNPACK"/ramdisk.cpio*; do
                [ -f "$f" ] || continue
                RAMDISK_SIZE=$(wc -c < "$f")
                case "$f" in
                    *.gz) RAMDISK_COMP="gzip" ;; *.lz4) RAMDISK_COMP="lz4" ;; *.lzo) RAMDISK_COMP="lzop" ;;
                    *.bz2) RAMDISK_COMP="bzip2" ;; *.xz) RAMDISK_COMP="xz" ;; *.zst) RAMDISK_COMP="zstd" ;;
                    *) RAMDISK_COMP="none" ;;
                esac
                log_info "Found ramdisk in $vb: $f ($RAMDISK_COMP, ${RAMDISK_SIZE} bytes)"
            done
            rm -rf "$VB_UNPACK"
        fi
        rm -f "$TMP_VB_CHECK"
    done
fi

rm -f "$TMP_BOOT"

# ============================================
# 7. KERNEL MODULES
# ============================================
log_header "7. KERNEL MODULES INFO"

MODULES_DIR="/vendor/lib/modules"
[ -d "/system/lib/modules" ] && MODULES_DIR="/system/lib/modules"
[ -d "/vendor_dlkm/lib/modules" ] && MODULES_DIR="/vendor_dlkm/lib/modules"

MODULES_JSON="[]"
MODULE_COUNT=0

if [ -d "$MODULES_DIR" ]; then
    log_info "Modules directory: $MODULES_DIR"
    MODULE_LIST=$(ls "$MODULES_DIR"/*.ko 2>/dev/null | head -50)
    if [ -n "$MODULE_LIST" ]; then
        MODULE_COUNT=$(echo "$MODULE_LIST" | wc -l)
        MODULES_JSON=$(echo "$MODULE_LIST" | xargs -n1 basename | sed 's/^/  "/;s/$/"/' | paste -sd, | sed 's/^/[/;s/$/]/')
        echo "$MODULE_LIST" | head -20 | while IFS= read -r line; do
            log_raw "$line"
        done
    fi
else
    log_warn "Modules directory not found"
fi

# Loaded modules
LOADED_MODULES=$(lsmod 2>/dev/null | tail -n +2 | awk '{print $1}' | sed 's/^/  "/;s/$/"/' | paste -sd, | sed 's/^/[/;s/$/]/')
LOADED_COUNT=$(echo "$LOADED_MODULES" | tr -d '[]" ' | tr ',' '\n' | grep -v '^$' | wc -l)
log_info "Loaded modules: $LOADED_COUNT"

json_add_str "modules_dir" "$MODULES_DIR"
json_add "available_modules" "$MODULES_JSON"
json_add_str "module_count" "$MODULE_COUNT"
json_add "loaded_modules" "$LOADED_MODULES"

# ============================================
# 8. AVB / VBMETA STATUS
# ============================================
log_header "8. AVB / VBMETA STATUS"

VBMETA_JSON="{}"
if command -v avbctl >/dev/null 2>&1; then
    AVB_OUT_FILE="$TMP_DIR/avb_out.txt"
    (
        avbctl get-verity
    ) > "$AVB_OUT_FILE" 2>&1
    AVB_OUT=$(cat "$AVB_OUT_FILE" 2>/dev/null)
    echo "$AVB_OUT" | while IFS= read -r line; do
        log_raw "$line"
    done
    VBMETA_JSON=$(echo "$AVB_OUT" | grep -v '^$' | sed 's/^/  "/;s/: /": "/;s/$/"/' | paste -sd, | sed 's/^/ {/;s/$/ }/')
    rm -f "$AVB_OUT_FILE"
else
    log_warn "avbctl not available"
fi

# vbmeta partitions
VB_PARTS=""
for part in vbmeta vbmeta_system vbmeta_vendor; do
    for suffix in "" "_a" "_b"; do
        p="/dev/block/by-name/${part}${suffix}"
        if [ -e "$p" ] || [ -L "$p" ]; then
            target=$(readlink -f "$p" 2>/dev/null)
            log_info "Found: $p -> $target"
            VB_PARTS="${VB_PARTS}{\"name\":\"${part}${suffix}\",\"path\":\"${target}\"},"
        fi
    done
done
VB_PARTS="[${VB_PARTS%,}]"

json_add "avb_status" "$VBMETA_JSON"
json_add "vbmeta_partitions" "$VB_PARTS"

# ============================================
# 9. KERNEL CMDLINE
# ============================================
log_header "9. KERNEL CMDLINE"

CMDLINE=$(cat /proc/cmdline)
log_info "$CMDLINE"
json_add_str "kernel_cmdline" "$(json_escape "$CMDLINE")"

# ============================================
# 10. RAMDISK CONTENT ANALYSIS (from boot)
# ============================================
log_header "10. RAMDISK CONTENT ANALYSIS (boot)"

KEY_FILES=""
INIT_RC_FILES="[]"
FSTAB_JSON=""

log_step "Copying full boot image for analysis"
TMP_BOOT="$TMP_DIR/boot_full.img"
run_cmd dd if="$BOOT_IMG" of="$TMP_BOOT"

if [ -x "$BIN_DIR/magiskboot" ]; then
    log_step "Unpacking boot image with magiskboot"
    MB_OUT_FILE="$TMP_DIR/mb_unpack_out.txt"
    (
        cd "$TMP_DIR" || exit 1
        "$BIN_DIR/magiskboot" unpack "$TMP_BOOT" 2>&1
    ) | tee "$MB_OUT_FILE" || log_warn "magiskboot unpack failed (ramdisk may be in vendor_boot)"
    rm -f "$MB_OUT_FILE"

    log_step "Checking for extracted ramdisk files"
    ls -la "$TMP_DIR"/ramdisk* 2>/dev/null | while IFS= read -r line; do log_raw "  $line"; done

    # Decompress ramdisk
    log_step "Decompressing ramdisk"
    for f in "$TMP_DIR"/ramdisk.cpio*; do
        [ -f "$f" ] || continue
        log_info "Found ramdisk file: $(basename "$f")"
        case "$f" in
            *.gz)  log_info "  -> gzip detected"; gunzip -c "$f" > "$TMP_DIR/ramdisk.cpio" 2>/dev/null ;;
            *.lz4) log_info "  -> lz4 detected"; lz4 -dc "$f" > "$TMP_DIR/ramdisk.cpio" 2>/dev/null ;;
            *.lzo) log_info "  -> lzop detected"; lzop -dc "$f" > "$TMP_DIR/ramdisk.cpio" 2>/dev/null ;;
            *.bz2) log_info "  -> bzip2 detected"; bzip2 -dc "$f" > "$TMP_DIR/ramdisk.cpio" 2>/dev/null ;;
            *.xz)  log_info "  -> xz detected"; xz -dc "$f" > "$TMP_DIR/ramdisk.cpio" 2>/dev/null ;;
            *.zst) log_info "  -> zstd detected"; zstd -dc "$f" > "$TMP_DIR/ramdisk.cpio" 2>/dev/null ;;
            *)     log_info "  -> no compression"; cp "$f" "$TMP_DIR/ramdisk.cpio" 2>/dev/null ;;
        esac
    done

    if [ -f "$TMP_DIR/ramdisk.cpio" ]; then
        RAMDISK_SIZE=$(wc -c < "$TMP_DIR/ramdisk.cpio")
        log_info "Decompressed ramdisk size: $RAMDISK_SIZE bytes ($((RAMDISK_SIZE/1024)) KB)"

        log_step "Extracting ramdisk cpio archive"
        mkdir -p "$TMP_DIR/ramdisk_extracted"
        (
            cd "$TMP_DIR/ramdisk_extracted" || exit 1
            cpio -idm < ../ramdisk.cpio 2>&1 | while IFS= read -r line; do log_raw "  $line"; done

            # Key files
            log_step "Searching for key ramdisk files"
            for fname in init.rc fstab.* init.*.rc ueventd.rc sepolicy; do
                find . -name "$fname" 2>/dev/null | head -5 | while IFS= read -r p; do
                    log_info "  Found: $p"
                    KEY_FILES="${KEY_FILES}\"${p}\","
                done
            done

            # All init rc files
            log_step "Listing all init RC files"
            INIT_RC_FILES=$(find . -name "init*.rc" -o -name "ueventd*.rc" 2>/dev/null | sed 's/^/  "/;s/$/"/' | paste -sd, | sed 's/^/[/;s/$/]/')
            log_info "Init RC files: $INIT_RC_FILES"

            # Fstab entries
            log_step "Parsing fstab files"
            for fstab in fstab.*; do
                [ -f "$fstab" ] && {
                    log_info "=== $fstab ==="
                    cat "$fstab" | grep -v '^#' | grep -v '^$' | while IFS= read -r line; do
                        log_info "  $line"
                    done
                    FSTAB_CONTENT=$(cat "$fstab" | grep -v '^#' | grep -v '^$' | json_escape)
                    FSTAB_JSON="${FSTAB_JSON}{\"file\":\"$fstab\",\"content\":\"$FSTAB_CONTENT\"},"
                }
            done
        )
    else
        log_warn "No ramdisk.cpio found after extraction - ramdisk likely in vendor_boot"
    fi
    rm -rf "$TMP_DIR"/ramdisk* "$TMP_DIR"/kernel* "$TMP_DIR"/dt* "$TMP_DIR"/cmdline.txt "$TMP_DIR"/header "$TMP_DIR"/chromeos "$TMP_DIR"/ramdisk_extracted 2>/dev/null
else
    log_warn "magiskboot not available, skipping ramdisk content analysis"
fi

if [ -n "$FSTAB_JSON" ]; then
    FSTAB_JSON="[${FSTAB_JSON%,}]"
else
    FSTAB_JSON="[]"
fi
json_add "ramdisk_key_files" "[${KEY_FILES%,}]"
json_add "init_rc_files" "$INIT_RC_FILES"
json_add "fstab_entries" "$FSTAB_JSON"

rm -f "$TMP_BOOT"

# ============================================
# 11. KERNEL CONFIG (IKCONFIG)
# ============================================
log_header "11. KERNEL CONFIG (IKCONFIG)"

KERNEL_CONFIG_JSON="{}"
HAS_IKCONFIG=0

if [ -f /proc/config.gz ]; then
    log_info "Found /proc/config.gz"
    zcat /proc/config.gz > "$TMP_DIR/kernel_config_full.txt"
    CONFIG_LINES=$(zcat /proc/config.gz | wc -l)
    CONFIG_SAMPLE=$(zcat /proc/config.gz | head -30 | json_escape)
    HAS_IKCONFIG=1
    log_info "Config lines: $CONFIG_LINES (saved to $TMP_DIR/kernel_config_full.txt)"
    cp "$TMP_DIR/kernel_config_full.txt" "${SCRIPT_DIR}/${DEVICE_CODENAME}_kernel_config.txt"
    log_info "Also copied to ${SCRIPT_DIR}/${DEVICE_CODENAME}_kernel_config.txt"
elif [ -x "$BIN_DIR/magiskboot" ]; then
    TMP_BOOT="$TMP_DIR/boot_config.img"
    run_cmd dd if="$BOOT_IMG" of="$TMP_BOOT"
    MB_OUT_FILE="$TMP_DIR/mb_unpack_out.txt"
    (
        cd "$TMP_DIR" || exit 1
        "$BIN_DIR/magiskboot" unpack "$TMP_BOOT" 2>&1
    ) | tee "$MB_OUT_FILE" || log_warn "magiskboot unpack failed (section 11)"
    rm -f "$MB_OUT_FILE"
    if [ -f "$TMP_DIR/kernel" ]; then
        "$BIN_DIR/magiskboot" decompress "$TMP_DIR/kernel" "$TMP_DIR/kernel_dec" 2>/dev/null
        CONFIG_SAMPLE=$(strings "$TMP_DIR/kernel_dec" | grep -E '^CONFIG_' | head -30 | json_escape)
        [ -n "$CONFIG_SAMPLE" ] && HAS_IKCONFIG=1
    fi
    rm -f "$TMP_BOOT" "$TMP_DIR"/kernel* 2>/dev/null
else
    log_warn "IKCONFIG not available"
fi

KERNEL_CONFIG_JSON="{\"has_ikconfig\":$HAS_IKCONFIG,\"sample\":\"$CONFIG_SAMPLE\"}"
json_add "kernel_config" "$KERNEL_CONFIG_JSON"

# ============================================
# 12. SELINUX INFO
# ============================================
log_header "12. SELINUX INFO"

SELINUX_STATUS=$(getenforce 2>/dev/null || echo "N/A")
POLICY_VERS=$(cat /sys/fs/selinux/policyvers 2>/dev/null || echo "N/A")
SEPOLICY_SIZE=0

log_info "SELinux status: $SELINUX_STATUS"
log_info "Policy version: $POLICY_VERS"

log_step "Copying boot image for sepolicy extraction"
TMP_BOOT="$TMP_DIR/boot_sepolicy.img"
run_cmd dd if="$BOOT_IMG" of="$TMP_BOOT"

if [ -x "$BIN_DIR/magiskboot" ]; then
    log_step "Unpacking boot image with magiskboot"
    MB_OUT_FILE="$TMP_DIR/mb_unpack_out.txt"
    (
        cd "$TMP_DIR" || exit 1
        "$BIN_DIR/magiskboot" unpack "$TMP_BOOT" 2>&1
    ) | tee "$MB_OUT_FILE" || log_warn "magiskboot unpack failed (section 12)"
    rm -f "$MB_OUT_FILE"

    log_step "Checking for extracted ramdisk files"
    ls -la "$TMP_DIR"/ramdisk* 2>/dev/null | while IFS= read -r line; do log_raw "  $line"; done

    # Decompress ramdisk
    log_step "Decompressing ramdisk"
    for f in "$TMP_DIR"/ramdisk.cpio*; do
        [ -f "$f" ] || continue
        log_info "Found ramdisk file: $(basename "$f")"
        case "$f" in
            *.gz)  log_info "  -> gzip detected"; gunzip -c "$f" > "$TMP_DIR/ramdisk.cpio" 2>/dev/null ;;
            *.lz4) log_info "  -> lz4 detected"; lz4 -dc "$f" > "$TMP_DIR/ramdisk.cpio" 2>/dev/null ;;
            *)     log_info "  -> no compression"; cp "$f" "$TMP_DIR/ramdisk.cpio" 2>/dev/null ;;
        esac
    done

    if [ -f "$TMP_DIR/ramdisk.cpio" ]; then
        RAMDISK_SIZE=$(wc -c < "$TMP_DIR/ramdisk.cpio")
        log_info "Decompressed ramdisk size: $RAMDISK_SIZE bytes ($((RAMDISK_SIZE/1024)) KB)"

        log_step "Extracting ramdisk cpio archive for sepolicy"
        mkdir -p "$TMP_DIR/rd_sepolicy"
        SEPOLICY_SIZE=$(
            cd "$TMP_DIR/rd_sepolicy" || exit 1
            cpio -idm < ../ramdisk.cpio 2>&1 | while IFS= read -r line; do log_raw "  $line"; done
            if [ -f sepolicy ]; then
                wc -c < sepolicy
            else
                echo 0
            fi
        )
        [ -n "$SEPOLICY_SIZE" ] || SEPOLICY_SIZE=0
        log_info "sepolicy in ramdisk: ${SEPOLICY_SIZE} bytes"
    else
        log_warn "No ramdisk.cpio found - sepolicy likely not in boot ramdisk"
    fi
    rm -rf "$TMP_DIR"/ramdisk* "$TMP_DIR"/kernel* "$TMP_DIR"/rd_sepolicy 2>/dev/null
else
    log_warn "magiskboot not available, skipping sepolicy extraction"
fi
rm -f "$TMP_BOOT"

json_add_str "selinux_status" "$SELINUX_STATUS"
json_add_str "selinux_policy_version" "$POLICY_VERS"
json_add_str "sepolicy_ramdisk_size" "$SEPOLICY_SIZE"

# ============================================
# 13. DYNAMIC PARTITIONS / SUPER
# ============================================
log_header "13. DYNAMIC PARTITIONS (SUPER)"

SUPER_JSON="{}"
HAS_SUPER=0

if [ -e /dev/block/by-name/super ] || [ -e /dev/block/mapper/super ]; then
    HAS_SUPER=1
    log_info "Dynamic Partitions detected"
    SUPER_DEV=$(readlink -f /dev/block/by-name/super 2>/dev/null || readlink -f /dev/block/mapper/super 2>/dev/null)
    SUPER_SIZE=$(blockdev --getsize64 "$SUPER_DEV" 2>/dev/null || echo 0)
    SUPER_GB=$(awk "BEGIN {printf \"%.2f\", $SUPER_SIZE/1024/1024/1024}")
    log_info "Super device: $SUPER_DEV"
    log_info "Super size: ${SUPER_GB} GB"

    LP_JSON="[]"
    for lp in /dev/block/mapper/*; do
        [ -b "$lp" ] && {
            lp_size=$(blockdev --getsize64 "$lp" 2>/dev/null || echo 0)
            lp_mb=$((lp_size/1024/1024))
            log_info "  $(basename "$lp"): ${lp_mb} MB"
            LP_JSON="${LP_JSON}{\"name\":\"$(basename "$lp")\",\"size_mb\":${lp_mb}},"
        }
    done
    LP_JSON="[${LP_JSON%,}]"

    # lpdump if available
    LPDUMP_OUT=""
    command -v lpdump >/dev/null && LPDUMP_OUT=$(lpdump "$SUPER_DEV" 2>/dev/null | head -30 | json_escape)

    SUPER_JSON="{\"device\":\"$SUPER_DEV\",\"size_gb\":$SUPER_GB,\"logical_partitions\":$LP_JSON,\"lpdump\":\"$LPDUMP_OUT\"}"
else
    log_info "Static partitions (no super)"
    SUPER_JSON="{\"has_super\":0}"
fi

json_add "dynamic_partitions" "$SUPER_JSON"

# ============================================
# 14. GKI / VENDOR BOOT INFO
# ============================================
log_header "14. GKI / VENDOR BOOT INFO"

GKI_PROPS=$(getprop | grep -i gki | sed 's/^/  /')
log_info "GKI Props:"
echo "$GKI_PROPS" | while IFS= read -r line; do
    log_raw "$line"
done

GKI_JSON="{}"
GKI_JSON=$(echo "$GKI_PROPS" | sed 's/\[\([^]]*\)\]: \(.*\)/"\1":"\2"/' | paste -sd, | sed 's/^/ {/;s/$/ }/')

VENDOR_BOOT="/dev/block/by-name/vendor_boot"
[ "$IS_AB" -eq 1 ] && [ -n "$SLOT_SUFFIX" ] && VENDOR_BOOT="/dev/block/by-name/vendor_boot$SLOT_SUFFIX"

VB_HEADER_JSON="{}"
VENDOR_BOOT_RAMDISK_COMP="unknown"
VENDOR_BOOT_RAMDISK_SIZE=0
if [ -e "$VENDOR_BOOT" ]; then
    log_info "vendor_boot found: $VENDOR_BOOT"
    TMP_VB="$TMP_DIR/vendor_boot_header.img"
    run_cmd dd if="$VENDOR_BOOT" of="$TMP_VB" bs=4096 count=1
    if [ -x "$BIN_DIR/magiskboot" ]; then
        VB_OUT_FILE="$TMP_DIR/mb_vb_out.txt"
        (
            "$BIN_DIR/magiskboot" unpack -h "$TMP_VB" 2>&1
        ) | tee "$VB_OUT_FILE"
        VB_OUT=$(cat "$VB_OUT_FILE" 2>/dev/null)
        echo "$VB_OUT" | head -20 | while IFS= read -r line; do
            log_raw "$line"
        done
        VB_HEADER_JSON=$(echo "$VB_OUT" | grep -E '^[A-Z_]+=' | sed 's/\([^=]*\)=\(.*\)/"\1":"\2"/' | paste -sd, | sed 's/^/ {/;s/$/ }/')
        rm -f "$VB_OUT_FILE"
    fi
    rm -f "$TMP_VB"

    # Also unpack full vendor_boot for ramdisk (GKI devices)
    log_step "Extracting ramdisk from vendor_boot"
    TMP_VB_FULL="$TMP_DIR/vendor_boot_full.img"
    run_cmd dd if="$VENDOR_BOOT" of="$TMP_VB_FULL"
    if [ -x "$BIN_DIR/magiskboot" ]; then
        MB_OUT_FILE="$TMP_DIR/mb_vb_unpack_out.txt"
        (
            cd "$TMP_DIR" || exit 1
            "$BIN_DIR/magiskboot" unpack "$TMP_VB_FULL" 2>&1
        ) | tee "$MB_OUT_FILE" || log_warn "magiskboot unpack failed (vendor_boot full)"
        rm -f "$MB_OUT_FILE"
        for f in "$TMP_DIR"/ramdisk.cpio*; do
            [ -f "$f" ] && VENDOR_BOOT_RAMDISK_SIZE=$(wc -c < "$f") && case "$f" in
                *.gz)  VENDOR_BOOT_RAMDISK_COMP="gzip" ;;
                *.lz4) VENDOR_BOOT_RAMDISK_COMP="lz4" ;;
                *.lzo) VENDOR_BOOT_RAMDISK_COMP="lzop" ;;
                *.bz2) VENDOR_BOOT_RAMDISK_COMP="bzip2" ;;
                *.xz)  VENDOR_BOOT_RAMDISK_COMP="xz" ;;
                *.zst) VENDOR_BOOT_RAMDISK_COMP="zstd" ;;
                *)     VENDOR_BOOT_RAMDISK_COMP="none" ;;
            esac
        done
        rm -f "$TMP_DIR"/ramdisk.cpio* "$TMP_DIR"/kernel* "$TMP_DIR"/dt* "$TMP_DIR"/cmdline.txt "$TMP_DIR"/header 2>/dev/null
    fi
    rm -f "$TMP_VB_FULL"
fi

INIT_BOOT="/dev/block/by-name/init_boot"
[ "$IS_AB" -eq 1 ] && [ -n "$SLOT_SUFFIX" ] && INIT_BOOT="/dev/block/by-name/init_boot$SLOT_SUFFIX"
HAS_INIT_BOOT=0
[ -e "$INIT_BOOT" ] && HAS_INIT_BOOT=1 && log_info "init_boot found: $INIT_BOOT"

json_add "gki_props" "$GKI_JSON"
json_add "vendor_boot_header" "$VB_HEADER_JSON"
json_add_str "vendor_boot_ramdisk_compression" "$VENDOR_BOOT_RAMDISK_COMP"
json_add_str "vendor_boot_ramdisk_size_bytes" "$VENDOR_BOOT_RAMDISK_SIZE"
json_add_str "has_init_boot" "$HAS_INIT_BOOT"
json_add_str "init_boot_path" "$INIT_BOOT"

# ============================================
# 15. RECOVERY PARTITION
# ============================================
log_header "15. RECOVERY PARTITION"

RECOVERY="/dev/block/by-name/recovery"
[ "$IS_AB" -eq 1 ] && [ -n "$SLOT_SUFFIX" ] && RECOVERY="/dev/block/by-name/recovery$SLOT_SUFFIX"

RECOVERY_JSON="{}"
if [ -e "$RECOVERY" ]; then
    REC_SIZE=$(blockdev --getsize64 "$RECOVERY" 2>/dev/null || echo 0)
    REC_MB=$((REC_SIZE/1024/1024))
    log_info "Recovery: $RECOVERY (${REC_MB} MB)"
    TMP_REC="$TMP_DIR/recovery_header.img"
    run_cmd dd if="$RECOVERY" of="$TMP_REC" bs=4096 count=1
    if [ -x "$BIN_DIR/magiskboot" ]; then
        REC_OUT_FILE="$TMP_DIR/mb_rec_out.txt"
        (
            "$BIN_DIR/magiskboot" unpack -h "$TMP_REC" 2>&1
        ) | tee "$REC_OUT_FILE"
        REC_OUT=$(cat "$REC_OUT_FILE" 2>/dev/null)
        echo "$REC_OUT" | head -10 | while IFS= read -r line; do
            log_raw "$line"
        done
        RECOVERY_JSON=$(echo "$REC_OUT" | grep -E '^[A-Z_]+=' | sed 's/\([^=]*\)=\(.*\)/"\1":"\2"/' | paste -sd, | sed 's/^/ {/;s/$/ }/')
        rm -f "$REC_OUT_FILE"
    fi
    rm -f "$TMP_REC"
    RECOVERY_JSON="{\"path\":\"$RECOVERY\",\"size_mb\":$REC_MB,\"header\":$RECOVERY_JSON}"
else
    log_info "No separate recovery partition (recovery-in-boot)"
    RECOVERY_JSON="{\"has_separate_recovery\":0}"
fi

json_add "recovery" "$RECOVERY_JSON"

# ============================================
# 16. DTB / DTBO DETAILS
# ============================================
log_header "16. DTB / DTBO DETAILS"

DTB_JSON="{}"
TMP_BOOT="$TMP_DIR/boot_dtb.img"
run_cmd dd if="$BOOT_IMG" of="$TMP_BOOT"

if [ -x "$BIN_DIR/magiskboot" ]; then
    MB_OUT_FILE="$TMP_DIR/mb_dtb_unpack_out.txt"
    (
        cd "$TMP_DIR" || exit 1
        "$BIN_DIR/magiskboot" unpack "$TMP_BOOT" 2>&1
    ) | tee "$MB_OUT_FILE" || log_warn "magiskboot unpack failed (DTB)"
    rm -f "$MB_OUT_FILE"
    for dtb in dtb dtb.img kernel_dtb; do
        if [ -f "$TMP_DIR/$dtb" ]; then
            DTB_SIZE=$(wc -c < "$TMP_DIR/$dtb")
            log_info "Found $dtb: ${DTB_SIZE} bytes"
            # Try fdtget
            FDT_OUT=""
            if command -v fdtget >/dev/null 2>&1; then
                FDT_OUT=$(fdtget / "$TMP_DIR/$dtb" 2>/dev/null | head -10 | json_escape)
                log_info "  fdtget: $FDT_OUT"
            fi
            # Board info from strings
            BOARD_STR=$(strings "$TMP_DIR/$dtb" | grep -iE 'board|model|compatible' | head -5 | json_escape)
            log_info "  Board strings: $BOARD_STR"
            DTB_JSON="{\"file\":\"$dtb\",\"size\":$DTB_SIZE,\"fdtget\":\"$FDT_OUT\",\"board_strings\":\"$BOARD_STR\"}"
        fi
    done
    rm -f "$TMP_DIR"/dtb* "$TMP_DIR"/kernel* "$TMP_DIR"/ramdisk* 2>/dev/null
fi

# dtbo partition
DTBO="/dev/block/by-name/dtbo"
[ "$IS_AB" -eq 1 ] && [ -n "$SLOT_SUFFIX" ] && DTBO="/dev/block/by-name/dtbo$SLOT_SUFFIX"
DTBO_JSON="{}"
if [ -e "$DTBO" ]; then
    DTBO_SIZE=$(blockdev --getsize64 "$DTBO" 2>/dev/null || echo 0)
    DTBO_MB=$((DTBO_SIZE/1024/1024))
    log_info "dtbo partition: $DTBO (${DTBO_MB} MB)"
    DTBO_JSON="{\"path\":\"$DTBO\",\"size_mb\":$DTBO_MB}"
fi

json_add "dtb_info" "$DTB_JSON"
json_add "dtbo_partition" "$DTBO_JSON"

rm -f "$TMP_BOOT"

# ============================================
# 17. FINALIZE JSON
# ============================================
log_header "17. FINALIZING OUTPUT"

# Add metadata
json_add_str "collected_at" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
json_add_str "script_version" "2.0"
json_add_str "device_codename" "$DEVICE_CODENAME"

json_finalize

# Cleanup
rm -rf "$TMP_DIR"

# ============================================
# 18. ANYKERNEL3 CONFIG SUMMARY
# ============================================
log_header "18. ANYKERNEL3 CONFIG SUMMARY"

log_raw ""
log_raw "# ========================================="
log_raw "# COPY THIS TO your anykernel.sh"
log_raw "# ========================================="
log_raw ""
log_raw "properties() { '"
log_raw "kernel.string=YourKernelName by YourName"
log_raw "do.devicecheck=1"
log_raw "do.modules=0          # Set 1 if you have modules in modules/"
log_raw "do.systemless=1"
log_raw "do.cleanup=1"
log_raw "do.cleanuponabort=0"
log_raw "device.name1=$DEVICE_CODENAME"

IDX=2
for cn in $(echo "$AK_CODENAMES" | tr ',' ' '); do
    [ "$cn" != "$DEVICE_CODENAME" ] && [ -n "$cn" ] && {
        log_raw "device.name$IDX=$cn"
        IDX=$((IDX + 1))
    }
done

while [ $IDX -le 5 ]; do
    log_raw "device.name$IDX="
    IDX=$((IDX + 1))
done

log_raw "supported.versions=$ANDROID_SDK"
log_raw "supported.patchlevels=$SECURITY_PATCH"
log_raw "supported.vendorpatchlevels=$VENDOR_PATCH"
log_raw "'; }"
log_raw ""
log_raw "# Boot partition config"
log_raw "BLOCK=auto"
log_raw "IS_SLOT_DEVICE=$IS_AB"
log_raw "RAMDISK_COMPRESSION=auto"
log_raw "PATCH_VBMETA_FLAG=auto"
log_raw ""
log_raw "# Import core"
log_raw ". tools/ak3-core.sh"
log_raw ""
log_raw "# Install"
log_raw "dump_boot"
log_raw "# ... your patches here ..."
log_raw "write_boot"

# ============================================
# DONE
# ============================================
log_header "DONE"
log_info "JSON output: $JSON_FILE"
log_info "Log output: $LOG_FILE"
log_info "Kernel config (if found): ${SCRIPT_DIR}/${DEVICE_CODENAME}_kernel_config.txt"
log_info "Use JSON with: cat $JSON_FILE | jq ."