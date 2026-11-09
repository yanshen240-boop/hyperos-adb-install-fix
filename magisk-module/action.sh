#!/system/bin/sh
# 模块「操作」按钮：立即重新应用一次（改完配置后不必重启）
MODDIR=${0%/*}

echo "HyperOS ADB Install Fix - 立即应用"
sh "$MODDIR/patch.sh"
echo
sh "$MODDIR/patch.sh" status
echo
echo "最近日志："
tail -n 12 "$MODDIR/patch.log" 2>/dev/null
