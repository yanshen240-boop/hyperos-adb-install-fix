#!/system/bin/sh
# 修复 HyperOS / MIUI 上「adb install 仍要求插入 SIM 卡 / 登录小米账号」的问题
# 原理：persist.security.adbinstall 只控制开发者选项里那个开关的“状态显示”，
#      真正拦截 adb install 的是手机管家 com.miui.securitycenter 里的两处配置。
#
# 用法（需要 root）：
#   adb push fix-adb-install.sh /data/local/tmp/
#   adb shell su -c "sh /data/local/tmp/fix-adb-install.sh"
#
# 无需重启，执行完直接测试 adb install。

echo "------ fix adb install ------" 

XML=/data/data/com.miui.securitycenter/shared_prefs/remote_provider_preferences.xml

if [ ! -f "$XML" ]; then
    echo "! 找不到 $XML"
    echo "! 如果不是小米/红米机器，或者手机管家被卸载/冻结过，本脚本不适用。"
    exit 2
fi

echo "0. 确保 USB 调试(安全设置) 与 fastboot 已开启"
setprop persist.security.adbinput 1 2>/dev/null || resetprop persist.security.adbinput 1
setprop persist.security.adbinstall 1 2>/dev/null || resetprop persist.security.adbinstall 1
setprop persist.fastboot.enable 1 2>/dev/null || resetprop persist.fastboot.enable 1

cp "$XML" "$XML.bak.$(date +%s)" 2>/dev/null
echo "1. 已备份原文件到 $XML.bak.*"

TMP="$XML.fix.tmp"

# 原地重写：保留 inode，从而保留属主、权限和 SELinux 上下文
# （用 sed -i 会新建文件，导致 SELinux 标签丢失，手机管家反而读不到）
apply_sed() {
    sed "$1" "$XML" > "$TMP" && cat "$TMP" > "$XML"
    rm -f "$TMP"
}

set_bool() {
    if grep -q "name=\"$1\"" "$XML"; then
        echo "   修改 $1 -> $2"
        apply_sed "/name=\"$1\"/s/value=\"[a-zA-Z]*\"/value=\"$2\"/"
    else
        echo "   写入 $1 -> $2"
        apply_sed "s#</map>#    <boolean name=\"$1\" value=\"$2\" />\n</map>#"
    fi
    grep "name=\"$1\"" "$XML"
}

echo "2. 打开「USB 安装」开关状态"
set_bool security_adb_install_enable true

echo "3. 关闭安装拦截（这一步才是 SIM 卡校验的真正来源）"
set_bool permcenter_install_intercept_enabled false

echo "4. 结束手机管家 remote 进程，让配置重新加载"
PID=$(pidof com.miui.securitycenter.remote)
if [ -n "$PID" ]; then
    kill -9 $PID
    echo "   killed pid $PID"
else
    echo "   进程未运行，跳过"
fi

echo "------ 完成，直接执行 adb install 测试 ------"
