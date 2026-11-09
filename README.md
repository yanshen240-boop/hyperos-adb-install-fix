# HyperOS ADB Install Fix

绕过 MIUI / HyperOS 在「USB 安装」上的小米账号 + SIM 卡校验，让 `adb install` 和 scrcpy 反控开箱可用。

适用于 **Magisk（含 Magisk Alpha）/ KernelSU / APatch**，需已解锁 Bootloader 并有 root。

> 本项目基于 [@CHERWING](https://github.com/CHERWING) 的 [xiaomi_usb_security_bypass](https://github.com/CHERWING/xiaomi_usb_security_bypass) 继续开发，补齐了 HyperOS 上的第二道校验。原始作者与相关分析文章的出处见[致谢](#致谢)。

## 为什么需要它

小米把「USB 调试」拆成了三个互相独立的开关，每个都要求登录小米账号并插入 SIM 卡：

| 开发者选项开关 | 底层属性 / 配置 |
|---|---|
| USB 调试(安全设置) —— 允许模拟点击 | `persist.security.adbinput` |
| USB 安装 —— 允许 `adb install` | `persist.security.adbinstall` |
| FASTBOOT 刷机模式 | `persist.fastboot.enable` |

常见误解是「把这三个属性置 1 就完事了」。**在 HyperOS 上不够** —— `adb install` 还有第二道独立校验，位于手机管家：

```
PackageManagerServiceImpl.verifyInstallFromShell
  → PmInjector.installVerify
  → com.miui.securitycenter/...AdbInstallActivity
```

真正的开关是 `/data/data/com.miui.securitycenter/shared_prefs/remote_provider_preferences.xml` 里的：

```xml
<boolean name="permcenter_install_intercept_enabled" value="false" />
```

本模块两处都处理，并在每次开机后自动重新应用。

## 目录结构

```
.
├── magisk-module/              模块源码（模块根目录平铺）
│   ├── module.prop             模块元信息
│   ├── system.prop             开机早期由 resetprop 应用的 persist 属性
│   ├── customize.sh            安装提示 + 脚本执行位
│   ├── service.sh              开机后应用，2 分钟内复查
│   ├── patch.sh                核心逻辑
│   ├── action.sh               Magisk「操作」按钮
│   ├── uninstall.sh            卸载时恢复安装拦截
│   └── META-INF/               Recovery 卡刷入口
├── build_module.py             一键打包
├── HyperOS-ADB-Install-Fix-v1.0.1.zip   成品刷机包
└── fix-adb-install.sh          独立修复脚本（不想装模块时用）
```

## 安装

```bash
git clone https://github.com/<owner>/<repo>.git
cd <repo>
python build_module.py          # 生成 zip
```

然后在 Magisk 应用 → 模块 → 从本地安装，选择生成的 zip，重启。

不想重启可以点模块的「操作」按钮，或：

```bash
adb push HyperOS-ADB-Install-Fix-v1.0.1.zip /storage/emulated/0/Download/
adb shell su -c "magisk --install-module /storage/emulated/0/Download/HyperOS-ADB-Install-Fix-v1.0.1.zip"
adb shell su -c "sh /data/adb/modules/hyperos_adb_install_fix/patch.sh"
```

## 验证

```bash
adb shell su -c "sh /data/adb/modules/hyperos_adb_install_fix/patch.sh status"
adb install app.apk
```

`patch.sh status` 会打印三个 persist 属性和两个手机管家配置项的当前值。

## 实测记录

在 Xiaomi M332BF / HyperOS OS4.0.6.0.XHPCNXM / Android 17 / Magisk Alpha 31000 上验证：

- 覆盖安装 `adb install -r` —— 通过
- 全新安装（卸载后重装）—— 通过
- 对照实验：把 `security_adb_install_enable` 改回 `false`、拦截键保持 `false`，安装**依然通过**
  → 说明 `security_adb_install_enable` 是干扰项，唯一必需的是 `permcenter_install_intercept_enabled=false`

日志中仍能看到 `AdbInstallActivity` 被拉起，但它在约 60ms 内自行 `onDestroy`，不弹窗直接放行。

## 已知限制

**开发者选项里「USB 安装」这个开关本身拨不动。** 拨动会触发 `AdbInstallVerifyActivity`（action `com.miui.securitycenter.action.ADB_INSTALL_VERIFY`），那是手机管家 APK 内的 Java 逻辑 + 账号/SIM 校验，不读任何属性，靠改配置无法影响，需要 Xposed / Zygisk hook 才能干预。

但这不影响功能 —— 开关显示为关时 `adb install` 依然可用。**不要拨它**，拨了也只会弹一次窗，配置值最后仍是 `true`。

## 实现要点

几个踩过的坑，改代码前建议先看：

**不能用 `sed -i`。** 它新建文件替换原文件，属主变 root、SELinux 上下文丢失，手机管家按 context 读不到这份 prefs，表现就是「改了没反应」。必须 `sed > tmp && cat tmp > 原文件`，保留原 inode。

**开机时序。** `/data/data` 是 CE 存储，设了锁屏密码的设备要先解锁屏幕才可读。`service.sh` 因此不是简单等 `sys.boot_completed`，而是轮询目标文件存在后再动手，最多等 10 分钟。

**权限位。** Magisk 各版本处理方式不同：

- `<= 26.x`：先 source `customize.sh`，再调 `set_permissions()`
- `>= 27`：先 `set_default_perm`（一律 0644），**然后**才 source `customize.sh`

所以覆盖 `set_permissions()` 在新版是死代码，必须在 `customize.sh` 体内直接 `chmod 0755`，同时保留钩子兼容老版本。

**运行时安装的位置。** 系统运行时装模块（`BOOTMODE=true`），文件落 `/data/adb/modules_update/<id>/`，`/data/adb/modules/<id>/` 只有 `module.prop` 和 `update` 标记，重启后才合并。别误判为安装失败。

## 安全提示

`permcenter_install_intercept_enabled=false` 关掉的是手机管家对**所有安装**的拦截，不只 adb。`persist.security.adbinput=1` 则意味着任何拿到数据线的人都能模拟点击。

用完建议停用模块，或手动把该键改回 `true`。

## 致谢

本项目的思路和代码基础来自以下作者与文章，在此明确标注出处：

| 来源 | 作者 / 提交者 | 沿用了什么 |
|---|---|---|
| [xiaomi_usb_security_bypass](https://github.com/CHERWING/xiaomi_usb_security_bypass) | [@CHERWING](https://github.com/CHERWING)<br>（唯一提交，2026-09-08） | **本项目的起点。** `system.prop` 的属性清单、`service.sh` 里 `setprop → resetprop → /product/bin/resetprop` 的三级降级写法、`module.prop` 的模块结构和 id 命名风格，均沿自此项目 |
| [enable-miui-adb](https://github.com/Ylarod/enable-miui-adb) | [@Ylarod](https://github.com/Ylarod)<br>（14 次提交） | 指出 `remote_provider_preferences.xml` 中 `security_adb_install_enable` 与 `permcenter_install_intercept_enabled` 两个键；以及「原地重写以保留 inode、属主和 SELinux 上下文」的处理方式 |
| [使用 root 跳过小米 USB 安装应用确认](https://bl.ocks.org/the-eric-kwok/19b378d5ff0b02271a8307b144a4db35) | the-eric-kwok | 最早分析出 `AdbInstallActivity` 读取 `permcenter_install_intercept_enabled` 作为判定依据 |
| [不登陆小米账号启用 MIUI 的 ADB 调试(安全设置)](https://blog.remiki.ren/archives/5/) | remiki | 「USB 调试(安全设置)」开关与 `persist.security.adbinput` 的对应关系 |
| [HyperCeiler](https://github.com/ReChronoRain/HyperCeiler) | [@ReChronoRain](https://github.com/ReChronoRain) 及贡献者 | 关于手机管家 `AdbInstallActivity` 拦截逻辑的逆向分析，用于确认校验位置 |

本仓库相对上述来源的增量：HyperOS 4 实机验证；区分 `AdbInstallVerifyActivity`（开关验证）与 `AdbInstallActivity`（安装拦截）两条独立链路；Magisk v31 安装器权限位变更的适配；CE 存储加密下的开机时序处理；以及 `.gitattributes` 对 LF 的强制约束。

## License

MIT
