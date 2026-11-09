# HyperOS ADB Install Fix

绕过 MIUI / HyperOS 上「USB 安装」的小米账号 + SIM 卡校验，让 `adb install` 直接可用。

适用于 **Magisk（含 Magisk Alpha）/ KernelSU / APatch**，需已解锁 Bootloader 并有 root。

## 它比 xiaomi_usb_security_bypass 多做了什么

`persist.security.adbinstall=1` 只控制开发者选项里那个开关的**状态显示**，并不负责拦截。
HyperOS 上 `adb install` 的实际拦截点在手机管家：

| 位置 | 键 | 需要的值 |
|---|---|---|
| `/data/data/com.miui.securitycenter/shared_prefs/remote_provider_preferences.xml` | `security_adb_install_enable` | `true` |
| 同上 | `permcenter_install_intercept_enabled` | `false` |

本模块两处都处理，并在每次开机后自动重新应用。

## 安装

1. Magisk / KernelSU 应用 → 模块 → **从本地安装**
2. 选择 `HyperOS-ADB-Install-Fix-v1.0.1.zip`
3. 重启

不想重启可以：安装后到模块列表点 **操作** 按钮，它会立刻应用一次并打印状态。
部分管理器不显示操作按钮，此时用命令行：

```bash
su -c sh /data/adb/modules/hyperos_adb_install_fix/patch.sh
```

## 验证

```bash
# 属性
adb shell getprop persist.security.adbinstall      # 1
adb shell getprop persist.security.adbinput        # 1
adb shell getprop persist.fastboot.enable          # 1

# 手机管家配置
adb shell "su -c 'sh /data/adb/modules/hyperos_adb_install_fix/patch.sh status'"

# 实测
adb install app.apk
```

## 没有生效怎么办

按顺序排查：

1. **日志**：`/data/adb/modules/hyperos_adb_install_fix/patch.log`，看是否有 `FAIL` 行。
2. **手机管家缓存**：设置 → 应用 → 手机管家 → **结束运行**，再 `adb install` 试一次。
3. **被云端覆盖**：`remote_provider_preferences.xml` 名字里的 `remote_provider` 意味着配置可能由云端下发。
   本模块已做「开机后 30 秒复查」，若仍被改回，把 `service.sh` 里最后的 `sleep 30` 调大，或降低复查间隔。
4. **锁屏密码**：`/data/data` 属于 CE 存储，开机后需**先解锁一次屏幕**，`service.sh` 才能读到文件。
   脚本已最多等待 10 分钟。
5. **不是拦截是别的问题**：抓日志确认错误码
   ```bash
   adb logcat | grep -iE "install|permcenter|securitycenter"
   ```
   若报的是 `INSTALL_FAILED_INVALID_APK` 之类，跟本模块无关。

## 文件说明

| 文件 | 作用 |
|---|---|
| `module.prop` | 模块元信息 |
| `system.prop` | 开机早期由 Magisk `resetprop` 应用 persist 属性 |
| `service.sh` | 开机后执行 `patch.sh`，30 秒后复查 |
| `patch.sh` | 核心逻辑：置属性 → 改 XML → 结束手机管家 remote 进程 |
| `action.sh` | 操作按钮：立即应用并打印状态 |
| `uninstall.sh` | 卸载时尽量把 `permcenter_install_intercept_enabled` 改回 `true` |
| `customize.sh` | 安装提示 + 脚本执行位 |
| `original_prefs.bak` | 首次修改前自动留存的原始配置（生成于模块目录） |
| `patch.log` | 运行日志，超过 64K 自动轮转为 `patch.log.old` |

## 回滚

```bash
su -c "cp /data/adb/modules/hyperos_adb_install_fix/original_prefs.bak \
      /data/data/com.miui.securitycenter/shared_prefs/remote_provider_preferences.xml"
su -c "kill -9 $(pidof com.miui.securitycenter.remote)"
```

注意 `cp` 会替换 inode，改完需要修复属主与 SELinux 上下文：

```bash
su -c "chown $(stat -c %u:%g /data/data/com.miui.securitycenter) $XML"
su -c "restorecon $XML"
```

## 安全提示

关掉 `permcenter_install_intercept_enabled` 等于取消手机管家对**所有安装**的二次确认（不止 adb）。
同时 `persist.security.adbinput=1` 意味着任何拿到数据线的人都能模拟点击。

建议：装完需要的包后，把本模块停用，或手动把 `permcenter_install_intercept_enabled` 改回 `true`。

## License

MIT
