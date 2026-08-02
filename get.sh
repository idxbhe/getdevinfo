#!/system/bin/sh
# get_device_info.sh - Collect device info for AnyKernel3
# Run as root: su -c "sh get_device_info.sh"
# Output: <script_dir>/<device_codename>.json + .log

# POSIX compliant - works with mksh, bash, dash, busybox sh
# NOTE: no `set -e` — on strict read-only root many dd/blockdev/getprop calls
# fail intermittently; we must not abort the whole collector on a single error.
# Guard critical operations individually with `|| true` / `2>/dev/null` instead.
set +e

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

# Run command with logging - output goes to stdout and log file.
# Never abort the script: pipe to tee in a subshell so failures are captured
# but do not propagate (no set -e in play anyway).
run_cmd() {
    log_cmd "$*"
    "$@" 2>&1 | tee -a "$LOG_FILE" || true
}

# Robust getprop: try system getprop, then scan common build.prop locations.
# On strict read-only root /system may be unreadable from the collector's
# selinux context, so every read is best-effort.
get_prop() {
    local val
    val=$(getprop "$1" 2>/dev/null)
    [ -n "$val" ] && { echo "$val"; return; }
    for d in / /system_root /system /vendor /product /system_ext /odm; do
        for f in default.prop build.prop; do
            val=$(file_getprop "$d/$f" "$1" 2>/dev/null)
            [ -n "$val" ] && { echo "$val"; return; }
        done
    done
    echo "N/A"
}

# file_getprop local copy (independent of busybox env quirks)
file_getprop() { grep "^$2=" "$1" 2>/dev/null | tail -n1 | cut -d= -f2-; }

# Safely run a block device read: returns non-zero if device missing or
# unreadable. Used to detect strict read-only partitions.
safe_dd() {
    # $1=if $2=of $3..=rest
    dd "$@" 2>/dev/null || return 1
}

# Detect partition real path across all common by-name layouts (read-only safe)
resolve_part() {
    local name="$1" p target
    for base in /dev/block/by-name /dev/block/bootdevice/by-name /dev/block/mapper; do
        for p in "$base/$name" "$base/$name$SLOT_SUFFIX" "$base/${name}_a" "$base/${name}_b"; do
            if [ -e "$p" ] || [ -L "$p" ]; then
                target=$(readlink -f "$p" 2>/dev/null || echo "$p")
                [ -e "$target" ] && { echo "$target"; return 0; }
            fi
        done
    done
    return 1
}

# Read-only check on a block device; returns 0 if path exists & is readable
part_readable() {
    local p="$1"
    [ -e "$p" ] || return 1
    dd if="$p" of=/dev/null bs=512 count=1 2>/dev/null || return 1
    return 0
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
    # Cross-check via partition existence (read-only safe)
    if [ -e /dev/block/by-name/boot_a ] || resolve_part boot_a >/dev/null 2>&1; then
        IS_AB=1
        ACTIVE_SLOT="_a"
        log_info "Device is A/B (detected via boot_a partition)"
    else
        log_info "Device is Non-A/B"
    fi
fi

json_add_str "is_ab_device" "$IS_AB"
json_add_str "active_slot" "$ACTIVE_SLOT"
json_add_str "slot_suffix" "$SLOT_SUFFIX"

# Partition scan (run in parent shell so JSON var is preserved)
log_step "Scanning partitions..."
PARTITIONS_JSON=""
add_part_entry() {
    local name="$1" path="$2"
    local target size size_mb
    target=$(readlink -f "$path" 2>/dev/null || echo "$path")
    size=$(blockdev --getsize64 "$target" 2>/dev/null || echo "0")
    size_mb=$((size / 1024 / 1024))
    log_info "  $name -> $target (${size_mb} MB)"
    PARTITIONS_JSON="${PARTITIONS_JSON}{\"name\":\"${name}\",\"path\":\"${target}\",\"size_mb\":${size_mb}},"
}

for part in boot dtbo vendor_boot init_boot vendor_kernel_boot recovery dtb vbmeta vbmeta_system vbmeta_vendor super; do
    for suffix in "" "_a" "_b"; do
        path="/dev/block/by-name/${part}${suffix}"
        if [ -e "$path" ] || [ -L "$path" ]; then
            add_part_entry "${part}${suffix}" "$path"
        fi
    done
done

# Platform by-name layout (symlinks resolving to real block devs)
for base in /dev/block/platform/*/by-name /dev/block/platform/*/*/by-name; do
    [ -d "$base" ] || continue
    for part in boot dtbo vendor_boot init_boot recovery vbmeta; do
        for p in "$base/$part" "$base/${part}_a" "$base/${part}_b"; do
            if { [ -e "$p" ] || [ -L "$p" ]; } && part_readable "$p"; then
                add_part_entry "$(basename "$p")" "$p"
            fi
        done
    done
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
RAMDISK_SZ=0
KERNEL_SZ=0
if resolve_part boot >/dev/null 2>&1; then
    BOOT_IMG=$(resolve_part boot)
    log_info "Analyzing boot image: $BOOT_IMG"
    TMP_BOOT="$TMP_DIR/boot_header.img"
    safe_dd if="$BOOT_IMG" of="$TMP_BOOT" bs=4096 count=1 || log_warn "Cannot read boot partition header (read-only?)"

    if [ -f "$TMP_BOOT" ]; then
        # Manual parse — independent of magiskboot, robust against "Corrupted" reports
        MAGIC=$(dd if="$TMP_BOOT" bs=1 count=8 2>/dev/null | od -An -tx1 | tr -d ' \n' || echo "")
        if [ "$MAGIC" = "414e44524f494421" ]; then
            # ANDROID! magic (v0-v3); header version is 4 bytes at offset 24 (le)
            HDR_VER=$(dd if="$TMP_BOOT" bs=1 skip=24 count=4 2>/dev/null | od -An -tu4 | tr -d ' \n' || echo "0")
            [ -z "$HDR_VER" ] && HDR_VER=0
            KERNEL_SZ=$(dd if="$TMP_BOOT" bs=1 skip=8  count=4 2>/dev/null | od -An -tu4 | tr -d ' \n' || echo "0")
            RAMDISK_SZ=$(dd if="$TMP_BOOT" bs=1 skip=12 count=4 2>/dev/null | od -An -tu4 | tr -d ' \n' || echo "0")
            log_info "Boot header v$HDR_VER (magic ANDROID!, kernel=${KERNEL_SZ}B, ramdisk=${RAMDISK_SZ}B)"
        elif dd if="$TMP_BOOT" bs=1 count=4 skip=0 2>/dev/null | od -An -c 2>/dev/null | grep -q E; then
            HDR_VER="4+ (ELF)"
            log_info "ELF format detected (header v4+ / GKI)"
        else
            log_warn "Unknown boot image format (magic: ${MAGIC:-empty})"
        fi

        if [ -x "$BIN_DIR/magiskboot" ]; then
            log_step "Running magiskboot unpack -h"
            MB_OUT_FILE="$TMP_DIR/mb_header_out.txt"
            "$BIN_DIR/magiskboot" unpack -h "$TMP_BOOT" > "$MB_OUT_FILE" 2>&1 || true
            MB_OUT=$(cat "$MB_OUT_FILE" 2>/dev/null)
            echo "$MB_OUT" | head -30 | while IFS= read -r line; do
                log_raw "$line"
            done
            # Build JSON only from KEY=VALUE lines magiskboot prints
            BOOT_HEADER_JSON=$(echo "$MB_OUT" | grep -E '^[A-Z_]+\s*\[' | sed 's/\([^[]*\)\[\([0-9]*\)\]/"\1":"\2"/' | paste -sd, 2>/dev/null | sed 's/^/{/;s/$/}/' || echo "")
            [ -z "$BOOT_HEADER_JSON" ] && BOOT_HEADER_JSON="{\"magic\":\"ANDROID!\",\"header_version\":\"$HDR_VER\",\"kernel_sz\":\"$KERNEL_SZ\",\"ramdisk_sz\":\"$RAMDISK_SZ\"}"
            rm -f "$MB_OUT_FILE"
        else
            BOOT_HEADER_JSON="{\"magic\":\"ANDROID!\",\"header_version\":\"$HDR_VER\",\"kernel_sz\":\"$KERNEL_SZ\",\"ramdisk_sz\":\"$RAMDISK_SZ\"}"
        fi
    fi
    rm -f "$TMP_BOOT"
else
    log_error "Boot partition not resolved by any by-name path"
    BOOT_IMG="N/A"
fi

json_add "boot_header" "$BOOT_HEADER_JSON"
json_add_str "boot_header_version" "$HDR_VER"
json_add_str "boot_partition" "$BOOT_IMG"
json_add_str "boot_ramdisk_sz_header" "$RAMDISK_SZ"

# ============================================
# 6. RAMDISK LOCATION & COMPRESSION PROBE  (CRITICAL for AK3 target)
# ============================================
# Goal: figure out WHERE the first-stage init ramdisk lives so AK3 flashes the
# right partition in the right mode. Common failure modes when wrong:
#   - boot.img RAMDISK_SZ=0 (skip_initramfs / OG-SAR) -> use split_boot/flash_boot (no ramdisk unpack)
#   - ramdisk in init_boot (Android 13+) -> BLOCK=init_boot, dump_boot/write_boot
#   - ramdisk in vendor_boot (GKI)        -> BLOCK=vendor_boot
# Probe candidates in priority order: init_boot > boot > vendor_boot > recovery.
log_header "6. RAMDISK LOCATION & COMPRESSION PROBE"

# helper: probe one partition; sets globals PROBE_COMP PROBE_SIZE PROBE_HVER on success
# args: <part_name> [workdir_label]
probe_part_ramdisk() {
    local part="$1" label="$2" p workdir hdrfile comp f sz magic hver
    PROBE_COMP=""; PROBE_SIZE=0; PROBE_HVER="unknown"
    p=$(resolve_part "$part" 2>/dev/null) || return 1
    [ -n "$p" ] || return 1
    part_readable "$p" || { log_warn "  $part unreadable (read-only?): $p"; return 1; }
    workdir="$TMP_DIR/probe_${label}"
    rm -rf "$workdir"; mkdir -p "$workdir"
    hdrfile="$workdir/hdr.img"
    safe_dd if="$p" of="$hdrfile" bs=4096 count=1 2>/dev/null || return 1
    magic=$(dd if="$hdrfile" bs=1 count=8 2>/dev/null | od -An -tx1 | tr -d ' \n')
    case "$magic" in
        414e44524f494421) PROBE_HVER=$(dd if="$hdrfile" bs=1 skip=24 count=4 2>/dev/null | od -An -tu4 | tr -d ' \n' || echo "0");;
        *) PROBE_HVER="unknown($magic)";;
    esac

    if [ -x "$BIN_DIR/magiskboot" ]; then
        ( cd "$workdir" && "$BIN_DIR/magiskboot" unpack "$hdrfile" >/dev/null 2>&1 ) || true
        # Note: unpack -h doesn't dump ramdisk content; do a full dd + unpack for size
        local fullimg="$workdir/full.img"
        if safe_dd if="$p" of="$fullimg" 2>/dev/null; then
            ( cd "$workdir" && rm -f ramdisk.cpio* kernel* dt* && "$BIN_DIR/magiskboot" unpack "$fullimg" >/dev/null 2>&1 ) || true
            for f in "$workdir"/ramdisk.cpio*; do
                [ -f "$f" ] || continue
                sz=$(wc -c < "$f" 2>/dev/null)
                [ -n "$sz" ] && [ "$sz" -gt 0 ] || continue
                case "$f" in
                    *.gz)   comp="gzip" ;;
                    *.lz4)  comp="lz4" ;;
                    *.lzo)  comp="lzop" ;;
                    *.bz2)  comp="bzip2" ;;
                    *.xz)   comp="xz" ;;
                    *.zst)  comp="zstd" ;;
                    *)      comp="none" ;;
                esac
                PROBE_COMP="$comp"; PROBE_SIZE="$sz"
                break
            done
        fi
    fi
    rm -rf "$workdir"
    [ -n "$PROBE_COMP" ] || return 1
    return 0
}

RAMDISK_COMP="unknown"
RAMDISK_SIZE=0
RAMDISK_LOCATION="unknown"           # boot | init_boot | vendor_boot | boot_sar(empty) | recovery_only
AK3_RECOMMENDED_BLOCK="auto"
AK3_INSTALL_MODE="split_boot,flash_boot"   # safe default
AK3_RAMDISK_COMPRESSION_OUT="auto"

# Probe in priority order, stop at first that yields a real ramdisk
PROBE_FOUND=0
for cand in init_boot:ramdisk_init boot:ramdisk_boot vendor_boot:ramdisk_vboot; do
    part="${cand%%:*}"; label="${cand##*:}"
    log_step "Probing $part for ramdisk..."
    if probe_part_ramdisk "$part" "$label"; then
        log_info "  $part: ramdisk found (comp=$PROBE_COMP, ${PROBE_SIZE}B, hdr=$PROBE_HVER)"
        RAMDISK_COMP="$PROBE_COMP"
        RAMDISK_SIZE="$PROBE_SIZE"
        case "$part" in
            init_boot)   RAMDISK_LOCATION="init_boot";   AK3_RECOMMENDED_BLOCK="init_boot"   ;;
            vendor_boot) RAMDISK_LOCATION="vendor_boot"; AK3_RECOMMENDED_BLOCK="vendor_boot" ;;
            boot)        RAMDISK_LOCATION="boot";        AK3_RECOMMENDED_BLOCK="boot"        ;;
        esac
        AK3_RAMDISK_COMPRESSION_OUT="auto"
        # hdr v4+ supports only lz4-l ramdisk (per ak3-core.sh:197); keep auto.
        AK3_INSTALL_MODE="dump_boot,write_boot"
        PROBE_FOUND=1
        break
    fi
done

# Decision logic for AK3 install mode when no ramdisk found in any candidate
if [ "$PROBE_FOUND" -eq 0 ]; then
    EARLY_CMDLINE=$(cat /proc/cmdline 2>/dev/null)
    if echo "$EARLY_CMDLINE" | grep -q 'skip_initramfs'; then
        RAMDISK_LOCATION="boot_sar(empty)"
        AK3_RECOMMENDED_BLOCK="boot"
        AK3_INSTALL_MODE="split_boot,flash_boot"   # NO ramdisk unpack/repack
        AK3_RAMDISK_COMPRESSION_OUT="none"
        log_info "Boot has NO ramdisk (skip_initramfs/OG-SAR). Use split_boot + flash_boot."
    elif resolve_part recovery >/dev/null 2>&1; then
        RAMDISK_LOCATION="recovery_only"
        AK3_RECOMMENDED_BLOCK="boot"
        AK3_INSTALL_MODE="split_boot,flash_boot"
        log_warn "No init ramdisk in boot/init_boot/vendor_boot. Recovery holds it; kernel-flash only via split_boot/flash_boot."
    else
        RAMDISK_LOCATION="none"
        AK3_RECOMMENDED_BLOCK="boot"
        AK3_INSTALL_MODE="split_boot,flash_boot"
        log_warn "No ramdisk located in any candidate partition; defaulting to boot + split_boot/flash_boot (safe / OG-AK mode)."
    fi
fi

# Clean up the leftover probe placeholder var (avoid confusion)
unset EARLY_CMDLINE CMDLINE_PLUGIN_PROBE 2>/dev/null

log_info "Ramdisk location: $RAMDISK_LOCATION"
log_info "Ramdisk compression: $RAMDISK_COMP"
log_info "Ramdisk size: $RAMDISK_SIZE bytes ($((RAMDISK_SIZE/1024)) KB)"
log_info "AK3 recommended BLOCK: $AK3_RECOMMENDED_BLOCK"
log_info "AK3 install mode: $AK3_INSTALL_MODE"

json_add_str "ramdisk_compression" "$RAMDISK_COMP"
json_add_str "ramdisk_size_bytes" "$RAMDISK_SIZE"
json_add_str "ramdisk_location" "$RAMDISK_LOCATION"
json_add_str "ak3_recommended_block" "$AK3_RECOMMENDED_BLOCK"
json_add_str "ak3_install_mode" "$AK3_INSTALL_MODE"
json_add_str "ak3_ramdisk_compression" "$AK3_RAMDISK_COMPRESSION_OUT"

# ============================================
# 7. KERNEL MODULES
# ============================================
log_header "7. KERNEL MODULES INFO"

# Priority: vendor_dlkm (GKI) > vendor > system  (read-only aware)
MODULES_DIR=""
for cand in /vendor_dlkm/lib/modules /vendor/lib/modules /system/lib/modules /system_ext/lib/modules; do
    if [ -d "$cand" ] && [ -r "$cand" ]; then
        MODULES_DIR="$cand"
        break
    fi
done

MODULES_JSON="[]"
MODULE_COUNT=0

if [ -n "$MODULES_DIR" ]; then
    log_info "Modules directory: $MODULES_DIR"
    # find is null-glob safe (ls *.ko would echo literal '*.ko' on empty dirs)
    MODULE_LIST=$(find "$MODULES_DIR" -maxdepth 1 -name '*.ko' 2>/dev/null | head -50)
    MODULE_COUNT=$(echo "$MODULE_LIST" | grep -c '\.ko$' 2>/dev/null)
    [ -z "$MODULE_COUNT" ] && MODULE_COUNT=0
    if [ "$MODULE_COUNT" -gt 0 ]; then
        MODULES_JSON=$(echo "$MODULE_LIST" | xargs -n1 basename 2>/dev/null | sed 's/^/"/;s/$/"/' | paste -sd, | sed 's/^/[/;s/$/]/')
        echo "$MODULE_LIST" | head -20 | while IFS= read -r line; do
            log_raw "  $line"
        done
        log_info "Found $MODULE_COUNT module(s)"
    else
        log_warn "Modules dir exists but contains no .ko files"
    fi
else
    log_warn "No readable modules directory under /vendor*, /system"
fi

# Loaded modules
if command -v lsmod >/dev/null 2>&1; then
    LOADED_LIST=$(lsmod 2>/dev/null | tail -n +2 | awk '{print $1}')
else
    LOADED_LIST=$(cut -d' ' -f1 /proc/modules 2>/dev/null)
fi
LOADED_COUNT=$(echo "$LOADED_LIST" | grep -c . 2>/dev/null)
[ -z "$LOADED_COUNT" ] && LOADED_COUNT=0
log_info "Loaded modules: $LOADED_COUNT"
if [ "$LOADED_COUNT" -gt 0 ]; then
    LOADED_MODULES=$(echo "$LOADED_LIST" | sed 's/^/"/;s/$/"/' | paste -sd, | sed 's/^/[/;s/$/]/')
else
    LOADED_MODULES="[]"
fi

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
# 10. RAMDISK CONTENT ANALYSIS  (uses RAMDISK_LOCATION from section 6)
# ============================================
log_header "10. RAMDISK CONTENT ANALYSIS"

KEY_FILES=""
INIT_RC_FILES="[]"
FSTAB_JSON=""

# Decompress helper: <compressed_file> <out_file>
decompress_to() {
    local in="$1" out="$2"
    case "$in" in
        *.gz)  gunzip -c  "$in" > "$out" 2>/dev/null ;;
        *.lz4) "$BIN_DIR/lz4" -dc "$in" > "$out" 2>/dev/null ;;
        *.lzo) lzop -dc    "$in" > "$out" 2>/dev/null ;;
        *.bz2) bzip2 -dc  "$in" > "$out" 2>/dev/null ;;
        *.xz)  xz -dc     "$in" > "$out" 2>/dev/null ;;
        *.zst) "$BIN_DIR/zstd" -dc "$in" > "$out" 2>/dev/null ;;
        *)     cp "$in" "$out" 2>/dev/null ;;
    esac
    [ -s "$out" ] || return 1
}

# Skip content analysis if section 6 detected no real ramdisk
if [ "$RAMDISK_LOCATION" = "boot_sar(empty)" ] || [ "$RAMDISK_LOCATION" = "none" ] || [ "$RAMDISK_LOCATION" = "recovery_only" ]; then
    log_warn "Skipping ramdisk content analysis (location=$RAMDISK_LOCATION)"
else
    # Determine which partition holds the ramdisk we just probed
    case "$RAMDISK_LOCATION" in
        init_boot)   RAMDISK_SRC_PART="init_boot" ;;
        vendor_boot) RAMDISK_SRC_PART="vendor_boot" ;;
        boot|*)      RAMDISK_SRC_PART="boot" ;;
    esac
    RAMDISK_SRC=$(resolve_part "$RAMDISK_SRC_PART" 2>/dev/null || echo "$BOOT_IMG")

    log_step "Copying full $RAMDISK_SRC_PART image for ramdisk content analysis"
    TMP_BOOT="$TMP_DIR/content_full.img"
    if ! safe_dd if="$RAMDISK_SRC" of="$TMP_BOOT" 2>/dev/null; then
        log_warn "Cannot read $RAMDISK_SRC_PART for content analysis (read-only?)"
    elif [ -x "$BIN_DIR/magiskboot" ]; then
        WORK="$TMP_DIR/content_unpack"
        rm -rf "$WORK"; mkdir -p "$WORK"
        ( cd "$WORK" && "$BIN_DIR/magiskboot" unpack "$TMP_BOOT" >/dev/null 2>&1 ) || log_warn "magiskboot unpack failed (content)"

        log_step "Decompressing ramdisk"
        CPIO_FILE=""
        for f in "$WORK"/ramdisk.cpio*; do
            [ -f "$f" ] || continue
            log_info "Found ramdisk file: $(basename "$f")"
            if decompress_to "$f" "$WORK/ramdisk.cpio" 2>/dev/null; then
                CPIO_FILE="$WORK/ramdisk.cpio"
                break
            fi
        done

        if [ -n "$CPIO_FILE" ] && [ -s "$CPIO_FILE" ]; then
            log_info "Decompressed ramdisk: $(wc -c < "$CPIO_FILE") bytes"
            EXTRACT_DIR="$WORK/extracted"
            mkdir -p "$EXTRACT_DIR"
            # cpio extraction in subshell is fine (no var assignment there now)
            ( cd "$EXTRACT_DIR" && cpio -idm < "$CPIO_FILE" >/dev/null 2>&1 ) || log_warn "cpio extract failed"

            # All file scanning/JSON building done in PARENT shell to preserve vars
            log_step "Searching for key ramdisk files"
            # Build KEY_FILES in PARENT shell (command substitution, not `| while read`
            # which would run in a subshell and discard the variable mutation).
            KEY_LIST=$(for fname in init.rc fstab.qcom fstab.qcom-first-stage fstab.* init.*.rc ueventd.rc ueventd.*.rc sepolicy; do
                find "$EXTRACT_DIR" -name "$fname" 2>/dev/null | head -5
            done | sed "s#^$EXTRACT_DIR/##" | sort -u)
            if [ -n "$KEY_LIST" ]; then
                while IFS= read -r rel; do
                    [ -n "$rel" ] || continue
                    log_info "  Found: $rel"
                    KEY_FILES="${KEY_FILES}\"$(json_escape "$rel")\","
                done <<EOF
$(printf '%s\n' "$KEY_LIST")
EOF
            fi
            unset KEY_LIST

            log_step "Listing all init RC files"
            INIT_RC_LIST=$(find "$EXTRACT_DIR" -name "init*.rc" -o -name "ueventd*.rc" 2>/dev/null | sed "s#^$EXTRACT_DIR/##" | sort)
            if [ -n "$INIT_RC_LIST" ]; then
                INIT_RC_FILES=$(echo "$INIT_RC_LIST" | sed 's/^/"/;s/$/"/' | paste -sd, | sed 's/^/[/;s/$/]/')
                log_info "Init RC files: $(echo "$INIT_RC_LIST" | tr '\n' ' ')"
            fi

            log_step "Parsing fstab files"
            for fstab in "$EXTRACT_DIR"/fstab.*; do
                [ -f "$fstab" ] || continue
                base=$(basename "$fstab")
                log_info "=== $base ==="
                FSTAB_CONTENT=$(grep -v '^#' "$fstab" 2>/dev/null | grep -v '^$' | json_escape)
                [ -n "$FSTAB_CONTENT" ] && FSTAB_JSON="${FSTAB_JSON}{\"file\":\"$base\",\"content\":\"$FSTAB_CONTENT\"},"
            done
        else
            log_warn "No ramdisk.cpio produced from $RAMDISK_SRC_PART content analysis"
        fi
        rm -rf "$WORK"
    fi
    rm -f "$TMP_BOOT"
fi

if [ -n "$FSTAB_JSON" ]; then
    FSTAB_JSON="[${FSTAB_JSON%,}]"
else
    FSTAB_JSON="[]"
fi
json_add "ramdisk_key_files" "[${KEY_FILES%,}]"
json_add "init_rc_files" "$INIT_RC_FILES"
json_add "fstab_entries" "$FSTAB_JSON"

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
    safe_dd if="$BOOT_IMG" of="$TMP_BOOT" 2>/dev/null || log_warn "Cannot read boot for IKCONFIG fallback"
    MB_OUT_FILE="$TMP_DIR/mb_unpack_out.txt"
    WORK="$TMP_DIR/ikconfig_unpack"; rm -rf "$WORK"; mkdir -p "$WORK"
    if [ -s "$TMP_BOOT" ]; then
        ( cd "$WORK" && "$BIN_DIR/magiskboot" unpack "$TMP_BOOT" >/dev/null 2>&1 ) || log_warn "magiskboot unpack failed (section 11)"
        if [ -f "$WORK/kernel" ]; then
            "$BIN_DIR/magiskboot" decompress "$WORK/kernel" "$WORK/kernel_dec" 2>/dev/null || true
            CONFIG_SAMPLE=$(strings "$WORK/kernel_dec" 2>/dev/null | grep -E '^CONFIG_' | head -30 | json_escape)
            [ -n "$CONFIG_SAMPLE" ] && HAS_IKCONFIG=1
        fi
    fi
    rm -rf "$WORK"; rm -f "$TMP_BOOT"
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

log_step "Sepolicy extraction (uses RAMDISK_LOCATION)"
SEPOLICY_SIZE=0
if [ "$RAMDISK_LOCATION" = "boot_sar(empty)" ] || [ "$RAMDISK_LOCATION" = "none" ] || [ "$RAMDISK_LOCATION" = "recovery_only" ]; then
    log_warn "Skipping sepolicy extraction (location=$RAMDISK_LOCATION)"
elif [ -x "$BIN_DIR/magiskboot" ]; then
    case "$RAMDISK_LOCATION" in
        init_boot)   SEP_PART="init_boot" ;;
        vendor_boot) SEP_PART="vendor_boot" ;;
        boot|*)      SEP_PART="boot" ;;
    esac
    SEP_SRC=$(resolve_part "$SEP_PART" 2>/dev/null || echo "$BOOT_IMG")
    WORK="$TMP_DIR/sepolicy_unpack"
    rm -rf "$WORK"; mkdir -p "$WORK"
    if safe_dd if="$SEP_SRC" of="$WORK/src.img" 2>/dev/null; then
        ( cd "$WORK" && "$BIN_DIR/magiskboot" unpack src.img >/dev/null 2>&1 ) || log_warn "magiskboot unpack failed (section 12)"
        CPIO=""
        for f in "$WORK"/ramdisk.cpio*; do
            [ -f "$f" ] || continue
            decompress_to "$f" "$WORK/ramdisk.cpio" 2>/dev/null && { CPIO="$WORK/ramdisk.cpio"; break; }
        done
        if [ -n "$CPIO" ] && [ -s "$CPIO" ]; then
            SE="$WORK/extracted"; mkdir -p "$SE"
            ( cd "$SE" && cpio -idm < "$CPIO" >/dev/null 2>&1 ) || true
            if [ -f "$SE/sepolicy" ]; then
                SEPOLICY_SIZE=$(wc -c < "$SE/sepolicy")
                log_info "sepolicy in $SEP_PART ramdisk: ${SEPOLICY_SIZE} bytes"
            else
                log_info "sepolicy not in $SEP_PART ramdisk (may be in vendor sepolicy)"
            fi
        else
            log_warn "No ramdisk.cpio from $SEP_PART for sepolicy extraction"
        fi
    else
        log_warn "Cannot read $SEP_PART for sepolicy (read-only?)"
    fi
    rm -rf "$WORK"
fi

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

VENDOR_BOOT=$(resolve_part vendor_boot 2>/dev/null || echo "")
VB_HEADER_JSON="{}"
VENDOR_BOOT_RAMDISK_COMP="unknown"
VENDOR_BOOT_RAMDISK_SIZE=0
if [ -n "$VENDOR_BOOT" ] && part_readable "$VENDOR_BOOT"; then
    log_info "vendor_boot present: $VENDOR_BOOT"
    # Pull header to a temp, read header version so we don't re-unpack big image
    TMP_VB="$TMP_DIR/vendor_boot_hdr.img"
    if safe_dd if="$VENDOR_BOOT" of="$TMP_VB" bs=4096 count=1 2>/dev/null; then
        VB_HDR_VER=$(dd if="$TMP_VB" bs=1 skip=24 count=4 2>/dev/null | od -An -tu4 | tr -d ' \n' || echo "0")
        [ -z "$VB_HDR_VER" ] && VB_HDR_VER=0
        # vendor_ramdisk_size lives at different offset per header version; parse SDK-style only if v3+
        VB_RAMDISK_SZ_HDR=$(dd if="$TMP_VB" bs=1 skip=12 count=4 2>/dev/null | od -An -tu4 | tr -d ' \n' || echo "0")
        VB_HEADER_JSON="{\"header_version\":\"$VB_HDR_VER\",\"ramdisk_sz_header\":\"$VB_RAMDISK_SZ_HDR\"}"
        log_info "  vendor_boot header v$VB_HDR_VER, ramdisk_sz(header)=$VB_RAMDISK_SZ_HDR"
    fi
    rm -f "$TMP_VB"
    # Detailed ramdisk compression/size come from section 6 probe result via RAMDISK_LOCATION
    if [ "$RAMDISK_LOCATION" = "vendor_boot" ]; then
        VENDOR_BOOT_RAMDISK_COMP="$RAMDISK_COMP"
        VENDOR_BOOT_RAMDISK_SIZE="$RAMDISK_SIZE"
    fi
else
    log_info "vendor_boot not present"
    VENDOR_BOOT=""
fi

INIT_BOOT=$(resolve_part init_boot 2>/dev/null || echo "")
HAS_INIT_BOOT=0
[ -n "$INIT_BOOT" ] && part_readable "$INIT_BOOT" 2>/dev/null && HAS_INIT_BOOT=1 && log_info "init_boot present: $INIT_BOOT"

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

RECOVERY=$(resolve_part recovery 2>/dev/null || echo "")
RECOVERY_JSON="{}"
if [ -z "$RECOVERY" ]; then
    log_info "No separate recovery partition (recovery-in-boot)"
    RECOVERY_JSON="{\"has_separate_recovery\":0}"
else
    REC_SIZE=$(blockdev --getsize64 "$RECOVERY" 2>/dev/null || echo 0)
    REC_MB=$((REC_SIZE/1024/1024))
    log_info "Recovery: $RECOVERY (${REC_MB} MB)"
    TMP_REC="$TMP_DIR/recovery_hdr.img"
    REC_HDR_VER="unknown"
    if safe_dd if="$RECOVERY" of="$TMP_REC" bs=4096 count=1 2>/dev/null; then
        REC_MAGIC=$(dd if="$TMP_REC" bs=1 count=8 2>/dev/null | od -An -tx1 | tr -d ' \n' || echo "")
        if [ "$REC_MAGIC" = "414e44524f494421" ]; then
            REC_HDR_VER=$(dd if="$TMP_REC" bs=1 skip=24 count=4 2>/dev/null | od -An -tu4 | tr -d ' \n' || echo "0")
        fi
    fi
    RECOVERY_JSON="{\"path\":\"$RECOVERY\",\"size_mb\":$REC_MB,\"header_version\":\"$REC_HDR_VER\"}"
    rm -f "$TMP_REC"
fi

json_add "recovery" "$RECOVERY_JSON"

# ============================================
# 16. DTB / DTBO DETAILS
# ============================================
log_header "16. DTB / DTBO DETAILS"

DTB_JSON="{}"
# Reuse the partition determined by section 6 for DTB source (boot or vendor_boot)
case "$RAMDISK_LOCATION" in
    init_boot|vendor_boot) DTB_SRC_PART="$RAMDISK_LOCATION" ;;
    *)                     DTB_SRC_PART="boot" ;;
esac
DTB_SRC=$(resolve_part "$DTB_SRC_PART" 2>/dev/null || echo "$BOOT_IMG")
TMP_BOOT="$TMP_DIR/dtb_src.img"

if [ -x "$BIN_DIR/magiskboot" ] && safe_dd if="$DTB_SRC" of="$TMP_BOOT" 2>/dev/null; then
    WORK="$TMP_DIR/dtb_unpack"
    rm -rf "$WORK"; mkdir -p "$WORK"
    ( cd "$WORK" && "$BIN_DIR/magiskboot" unpack "$TMP_BOOT" >/dev/null 2>&1 ) || log_warn "magiskboot unpack failed (DTB)"
    for dtb in dtb dtb.img kernel_dtb; do
        if [ -f "$WORK/$dtb" ]; then
            DTB_SIZE=$(wc -c < "$WORK/$dtb" 2>/dev/null || echo 0)
            log_info "Found $dtb: ${DTB_SIZE} bytes"
            FDT_MODEL=""; FDT_COMPAT=""
            # CORRECT fdtget usage: fdtget <file> <node> <property>
            if [ -x "$BIN_DIR/fdtget" ]; then
                FDT_MODEL=$("$BIN_DIR/fdtget" "$WORK/$dtb" / model 2>/dev/null)
                FDT_COMPAT=$("$BIN_DIR/fdtget" "$WORK/$dtb" / compatible 2>/dev/null | tr '\n' ' ')
                [ -n "$FDT_MODEL" ]   && log_info "  fdtget / model: $FDT_MODEL"
                [ -n "$FDT_COMPAT" ] && log_info "  fdtget / compatible: $FDT_COMPAT"
            fi
            # Keep board_strings via fdtget only — strings grep on compiled DTB is unreliable
            DTB_JSON="{\"file\":\"$dtb\",\"size\":$DTB_SIZE,\"model\":\"$(json_escape "$FDT_MODEL")\",\"compatible\":\"$(json_escape "$FDT_COMPAT")\"}"
            break
        fi
    done
    rm -rf "$WORK"
fi
rm -f "$TMP_BOOT"

# dtbo partition
DTBO=$(resolve_part dtbo 2>/dev/null || echo "")
DTBO_JSON="{}"
if [ -n "$DTBO" ] && part_readable "$DTBO"; then
    DTBO_SIZE=$(blockdev --getsize64 "$DTBO" 2>/dev/null || echo 0)
    DTBO_MB=$((DTBO_SIZE/1024/1024))
    log_info "dtbo partition: $DTBO (${DTBO_MB} MB)"
    DTBO_JSON="{\"path\":\"$DTBO\",\"size_mb\":$DTBO_MB}"
fi

json_add "dtb_info" "$DTB_JSON"
json_add "dtbo_partition" "$DTBO_JSON"

# ============================================
# 17. FINALIZE JSON
# ============================================
log_header "17. FINALIZING OUTPUT"

# Add metadata (do NOT re-emit device_codename — already added in section 1)
json_add_str "collected_at" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
json_add_str "script_version" "2.1"

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
log_raw "# (auto-derived from probe results — review before use)"
log_raw "# ========================================="
log_raw ""

# Build the AK3-supported.versions string  (Android release, NOT SDK).
# AK3 README format: "8.1.0" or "7.1.2 - 9". When SDK-based fallback is needed
# (only if ANDROID_VER unreadable), we skip the line so AK3 disables the check
# (cleaner than emitting an SDK int that never matches a real release string).
if [ -n "$ANDROID_VER" ] && [ "$ANDROID_VER" != "N/A" ]; then
    SUPPORTED_VERSIONS_LINE="supported.versions=$ANDROID_VER"
else
    SUPPORTED_VERSIONS_LINE="# supported.versions=  # Android version unreadable - check disabled"
fi

# Patchlevel: AK3 expects YYYY-MM. Truncate to 7 chars defensively.
patch_ym() { echo "$1" | cut -c1-7; }
SP_YM=$(patch_ym "$SECURITY_PATCH"); VP_YM=$(patch_ym "$VENDOR_PATCH")

log_raw "properties() { '"
log_raw "kernel.string=YourKernelName by YourName"
log_raw "do.devicecheck=1"
log_raw "do.modules=$([ "$MODULE_COUNT" -gt 0 ] 2>/dev/null && echo 1 || echo 0)          # ${MODULE_COUNT:-0} module(s) detected"
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

log_raw "$SUPPORTED_VERSIONS_LINE"
[ -n "$SP_YM" ] && [ "$SP_YM" != "N/A" ] && log_raw "supported.patchlevels=$SP_YM"
[ -n "$VP_YM" ] && [ "$VP_YM" != "N/A" ] && log_raw "supported.vendorpatchlevels=$VP_YM"
log_raw "'; }"
log_raw ""
log_raw "# Boot partition config (derived from probe: ramdisk_location=$RAMDISK_LOCATION)"
log_raw "BLOCK=$AK3_RECOMMENDED_BLOCK"
log_raw "IS_SLOT_DEVICE=$IS_AB"
log_raw "RAMDISK_COMPRESSION=$AK3_RAMDISK_COMPRESSION_OUT"
log_raw "PATCH_VBMETA_FLAG=auto"
log_raw ""
log_raw "# Import core"
log_raw ". tools/ak3-core.sh"
log_raw ""
log_raw "# Install"
if echo "$AK3_INSTALL_MODE" | grep -q split_boot; then
    log_raw "split_boot   # no ramdisk unpack (ramdisk location: $RAMDISK_LOCATION)"
    log_raw "# ... your kernel-only patches here ..."
    log_raw "flash_boot"
else
    log_raw "dump_boot"
    log_raw "# ... your ramdisk patches here ..."
    log_raw "write_boot"
fi
log_raw ""
log_raw "# Probe summary:"
log_raw "## ramdisk_location=$RAMDISK_LOCATION  comp=$RAMDISK_COMP  size=${RAMDISK_SIZE}B"
log_raw "## boot_header_version=$HDR_VER  is_ab=$IS_AB  ramdisk_size_header=${RAMDISK_SZ}B"

# ============================================
# DONE
# ============================================
log_header "DONE"
log_info "JSON output: $JSON_FILE"
log_info "Log output: $LOG_FILE"
log_info "Kernel config (if found): ${SCRIPT_DIR}/${DEVICE_CODENAME}_kernel_config.txt"
log_info "Use JSON with: cat $JSON_FILE | jq ."