#!/system/bin/sh
# 卸载时尽量把「安装拦截」恢复为 true，避免模块移除后留下安全缺口。
# 说明：uninstall.sh 在重启过程中执行，此时 /data 可能还未解密，
# 若执行失败属正常，重启后可手动把 permcenter_install_intercept_enabled 改回 true。
XML=/data/data/com.miui.securitycenter/shared_prefs/remote_provider_preferences.xml

[ -f "$XML" ] || exit 0

TMP="$XML.mod.tmp"
sed "/name=\"permcenter_install_intercept_enabled\"/s/value=\"false\"/value=\"true\"/" "$XML" > "$TMP" 2>/dev/null
if [ -s "$TMP" ]; then
    cat "$TMP" > "$XML"
fi
rm -f "$TMP"

PIDS=$(pidof com.miui.securitycenter.remote 2>/dev/null)
[ -n "$PIDS" ] && kill -9 $PIDS 2>/dev/null

exit 0
