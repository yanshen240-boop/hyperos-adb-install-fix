#!/system/bin/sh
# 安装时由 Magisk / Magisk Alpha / KernelSU 的 installer 执行

ui_print " "
ui_print "****************************************"
ui_print " HyperOS ADB Install Fix  v1.0.1"
ui_print " 绕过「USB 安装」的小米账号 / SIM 卡校验"
ui_print "****************************************"
ui_print " "

if [ "$BOOTMODE" != "true" ]; then
    ui_print "! 检测到非 App 内安装（可能是第三方 Recovery）"
    ui_print "! 建议改用 Magisk 应用 → 模块 → 从本地安装"
    ui_print " "
fi

# MIUI / HyperOS 检测（rom 版本属性）
MIUI_VER=$(getprop ro.miui.ui.version.name)
HYPER_VER=$(getprop ro.mi.os.version.name)
if [ -n "$HYPER_VER" ]; then
    ui_print "- 检测到 HyperOS: $HYPER_VER"
elif [ -n "$MIUI_VER" ]; then
    ui_print "- 检测到 MIUI: $MIUI_VER"
else
    ui_print "! 未检测到 MIUI / HyperOS，本模块可能无效"
fi

if [ -f /data/data/com.miui.securitycenter/shared_prefs/remote_provider_preferences.xml ]; then
    ui_print "- 手机管家配置文件已就位"
else
    ui_print "! 未读到手机管家配置（/data 未解密属正常，开机后会自动重试）"
fi

ui_print " "
ui_print "- 重启后生效；也可以在模块列表点「操作」立即应用"
ui_print "- 日志: /data/adb/modules/hyperos_adb_install_fix/patch.log"
ui_print " "

# ---- 脚本执行位 ----
# Magisk 各版本对权限的处理不一样：
#   <= 26.x : 先 source customize.sh，之后才调用 set_permissions()
#   >= 27   : 先 set_default_perm（一律 0644），然后才 source customize.sh
# 所以不能只靠 set_permissions 钩子，必须在 customize.sh 体内直接 chmod，
# 同时保留 set_permissions 以兼容老版本。
chmod_scripts() {
    for f in service.sh patch.sh action.sh uninstall.sh; do
        [ -f "$MODPATH/$f" ] && chmod 0755 "$MODPATH/$f"
    done
}

set_permissions() {
    set_perm_recursive "$MODPATH" 0 0 0755 0644
    chmod_scripts
}

chmod_scripts
