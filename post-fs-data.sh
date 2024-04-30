#!/system/bin/sh
# Please don't hardcode /magisk/modname/... ; instead, please use $MODDIR/...
# This will make your scripts compatible even if Magisk change its mount point in the future
MODDIR=${0%/*}

# This script will be executed in post-fs-data mode
# More info in the main Magisk thread

set_context() {
    [ "$(getenforce)" = "Enforcing" ] || return 0

    default_selinux_context=u:object_r:system_file:s0
    selinux_context=$(ls -Zd $1 | awk '{print $1}')

    if [ -n "$selinux_context" ] && [ "$selinux_context" != "?" ]; then
        chcon -R $selinux_context $2
    else
        chcon -R $default_selinux_context $2
    fi
}

SYS_CACERTS_DIR=/system/etc/security/cacerts
MOD_CACERTS_DIR="${MODDIR}/${SYS_CACERTS_DIR}"
USER_CACERTS=/data/misc/user/*/cacerts-added/*
USER_CACERTS_NUM="$(ls -1 $USER_CACERTS | wc -l)"

if [ $USER_CACERTS_NUM -eq 0 ]; then
    exit 0
fi

mkdir -p "$MOD_CACERTS_DIR"
rm "$MOD_CACERTS_DIR"/*
cp -f $USER_CACERTS "$MOD_CACERTS_DIR"
chown -R 0:0 "$MOD_CACERTS_DIR"
set_context "$SYS_CACERTS_DIR" "$MOD_CACERTS_DIR"

# Android 14 support
# Since Magisk ignore /apex for module file injections, use non-Magisk way
APEX_CACERTS_DIR=/apex/com.android.conscrypt/cacerts
TMP_CACERTS_DIR=/data/local/tmp/tmp-ca-copy
if [ -d "$APEX_CACERTS_DIR" ]; then
    # Clone directory into tmpfs
    rm -f "$TMP_CACERTS_DIR"
    mkdir -p "$TMP_CACERTS_DIR"
    mount -t tmpfs tmpfs "$TMP_CACERTS_DIR"
    cp -f "$APEX_CACERTS_DIR"/* "$TMP_CACERTS_DIR"

    # Do the same as in Magisk module
    cp -f $USER_CACERTS "$TMP_CACERTS_DIR"
    chown -R 0:0 "$TMP_CACERTS_DIR"
    set_context "$APEX_CACERTS_DIR" "$TMP_CACERTS_DIR"

    # Mount directory inside APEX if it is valid, and remove temporary one.
    mount --bind "$TMP_CACERTS_DIR" "$APEX_CACERTS_DIR"
    for pid in 1 $(pgrep zygote) $(pgrep zygote64); do
        nsenter --mount=/proc/${pid}/ns/mnt -- \
            /bin/mount --bind "$TMP_CACERTS_DIR" "$APEX_CACERTS_DIR"
    done

    umount "$TMP_CACERTS_DIR"
    rmdir "$TMP_CACERTS_DIR"
fi
