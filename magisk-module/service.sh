#!/system/bin/sh
# 开机后自动应用一次，并在稍后复查一次（防止云端配置回写）
case "$0" in
    */*) MODDIR=${0%/*} ;;
    *)   MODDIR=. ;;
esac
XML=/data/data/com.miui.securitycenter/shared_prefs/remote_provider_preferences.xml

# 1) 等待开机完成
i=0
while [ "$(getprop sys.boot_completed)" != "1" ] && [ $i -lt 240 ]; do
    sleep 2
    i=$((i + 1))
done

# 2) 等待 CE 存储解密。
# 开启了锁屏密码的设备，/data/data 要等用户解锁后才会出现，
# 所以这里持续探测文件是否存在，最多等 10 分钟。
i=0
while [ ! -f "$XML" ] && [ $i -lt 120 ]; do
    sleep 5
    i=$((i + 1))
done

# 3) 再等一会儿，避开开机瞬间手机管家的初始化
sleep 5
sh "$MODDIR/patch.sh"

# 4) 30 秒后复查。remote_provider_preferences 可能被云端下发覆盖，
#    这一步把它拉回来；若值本来就没变，patch.sh 会直接跳过，几乎无开销。
sleep 30
sh "$MODDIR/patch.sh"
