#!/system/bin/sh
# HyperOS ADB Install Fix - 核心执行脚本
# 被 service.sh（开机）、action.sh（操作按钮）、以及手动调用共用
#
# 用法：
#   sh patch.sh          立即应用
#   sh patch.sh status   只查看当前状态

case "$0" in
    */*) MODDIR=${0%/*} ;;
    *)   MODDIR=. ;;
esac
XML=/data/data/com.miui.securitycenter/shared_prefs/remote_provider_preferences.xml
LOG=$MODDIR/patch.log
BAK=$MODDIR/original_prefs.bak

# 日志超过 64K 轮转一次，防止无限增长
if [ -f "$LOG" ] && [ "$(wc -c < "$LOG" | tr -d ' ')" -gt 65536 ]; then
    mv -f "$LOG" "$LOG.old"
fi

echo_log() {
    echo "[$(date '+%m-%d %H:%M:%S')] $*" >> "$LOG"
}

# ---------- 读取 XML 里的布尔值 ----------
get_bool() {
    [ -f "$XML" ] || return 1
    sed -n "s/.*name=\"$1\"[^>]*value=\"\([a-zA-Z]*\)\".*/\1/p" "$XML" 2>/dev/null | head -n 1
}

show_status() {
    echo "------ 当前状态 ------"
    echo "persist.security.adbinput   = $(getprop persist.security.adbinput)"
    echo "persist.security.adbinstall = $(getprop persist.security.adbinstall)"
    echo "persist.fastboot.enable     = $(getprop persist.fastboot.enable)"
    if [ -f "$XML" ]; then
        echo "security_adb_install_enable          = $(get_bool security_adb_install_enable)"
        echo "permcenter_install_intercept_enabled = $(get_bool permcenter_install_intercept_enabled)"
    else
        echo "手机管家配置不存在：$XML"
    fi
}

if [ "$1" = "status" ]; then
    show_status
    exit 0
fi

echo_log "==== 开始应用 ===="

# ---------- 第一步：persist 属性 ----------
# setprop 被 SELinux 拦时自动降级到 resetprop（resetprop 直写内存，不走 property_service）
set_prop() {
    [ "$(getprop "$1")" = "$2" ] && return 0
    setprop "$1" "$2" 2>/dev/null
    [ "$(getprop "$1")" = "$2" ] && return 0
    if command -v resetprop >/dev/null 2>&1; then
        resetprop "$1" "$2" 2>/dev/null
        [ "$(getprop "$1")" = "$2" ] && return 0
    fi
    for rp in /data/adb/magisk/resetprop /data/adb/ksu/bin/resetprop /data/adb/ap/bin/resetprop /product/bin/resetprop; do
        if [ -x "$rp" ]; then
            "$rp" "$1" "$2" 2>/dev/null
            [ "$(getprop "$1")" = "$2" ] && return 0
        fi
    done
    return 1
}

set_prop persist.security.adbinput 1 && echo_log "OK   persist.security.adbinput=1" || echo_log "FAIL persist.security.adbinput"
set_prop persist.security.adbinstall 1 && echo_log "OK   persist.security.adbinstall=1" || echo_log "FAIL persist.security.adbinstall"
set_prop persist.fastboot.enable 1 && echo_log "OK   persist.fastboot.enable=1" || echo_log "FAIL persist.fastboot.enable"

# ---------- 第二步：手机管家配置 ----------
if [ ! -f "$XML" ]; then
    echo_log "SKIP 找不到 $XML（非小米系统，或 /data 尚未解密）"
    exit 3
fi

# 首次修改前留一份原始备份，方便回滚
[ -f "$BAK" ] || cp -p "$XML" "$BAK" 2>/dev/null

CHANGED=0

# 关键：不能用 sed -i。
# sed -i 会新建文件替换掉原文件，属主变成 root、SELinux 上下文变成 app_data_file 之外的标签，
# 手机管家按 context 读不到这份 prefs，表现就是"改了没用"。
# 这里用 cat 覆写原 inode，属主 / 权限 / SELinux 上下文全部保留。
set_bool() {
    CUR=$(get_bool "$1")
    if [ "$CUR" = "$2" ]; then
        echo_log "SKIP $1 已是 $2"
        return 0
    fi
    TMP="$XML.mod.tmp"
    if grep -q "name=\"$1\"" "$XML"; then
        sed "/name=\"$1\"/s/value=\"[a-zA-Z]*\"/value=\"$2\"/" "$XML" > "$TMP" 2>/dev/null
    else
        # 键不存在时插到 </map> 前面（用 & 引用匹配内容，避免依赖 sed 的 \n 扩展）
        sed "s#</map>#    <boolean name=\"$1\" value=\"$2\" />&#" "$XML" > "$TMP" 2>/dev/null
    fi
    if [ ! -s "$TMP" ]; then
        rm -f "$TMP"
        echo_log "FAIL $1 生成临时文件失败"
        return 1
    fi
    cat "$TMP" > "$XML"
    rm -f "$TMP"
    NOW=$(get_bool "$1")
    if [ "$NOW" = "$2" ]; then
        echo_log "OK   $1: $CUR -> $NOW"
        CHANGED=1
        return 0
    fi
    echo_log "FAIL $1 写入后仍为 $NOW"
    return 1
}

set_bool security_adb_install_enable true
set_bool permcenter_install_intercept_enabled false

# ---------- 第三步：让配置重新加载 ----------
# 这两个值由手机管家的 remote provider 进程持有缓存，不结束进程它不会重读文件
kill_sc() {
    for name in com.miui.securitycenter.remote; do
        PIDS=$(pidof "$name" 2>/dev/null)
        if [ -z "$PIDS" ]; then
            PIDS=$(ps -A -o PID,NAME 2>/dev/null | grep -w "$name" | awk '{print $1}' | tr '\n' ' ')
        fi
        if [ -n "$PIDS" ]; then
            kill -9 $PIDS 2>/dev/null
            echo_log "KILL $name ($PIDS)"
        fi
    done
}

if [ "$CHANGED" = "1" ]; then
    kill_sc
else
    echo_log "配置无需改动，不重启手机管家"
fi

echo_log "==== 结束 ===="
exit 0
