# Daily Wallpaper · 每日壁纸

标准 macOS 菜单栏应用：每天获取 Bing 壁纸，跟随系统明暗模式切换原图和深色版。双击启动，不显示 Dock 图标或主窗口，点击右上角的图片图标操作。

- 每天本地时间 9:00 更新；无缓存时立即下载，错过更新时间会在启动或唤醒后补更新。
- 深色版压低高光并适度降低曝光，原图单独保留；外观切换无需重新下载。
- 下载失败保留上次壁纸，10 分钟后重试。
- 更新时核对本地当天日期与照片标识；上游仍是旧日期或旧照片时保留当前壁纸，10 分钟后重试。当日相同照片复用缓存，链接变化时额外比较原图内容。
- 菜单提供立即更新、打开壁纸目录、关于和退出。
- “当前照片”子菜单显示照片说明、照片日期、来源地区和上次确认时间，并可打开本地原图；鼠标悬停菜单栏图标也可查看照片说明。
- 同一用户只运行一个实例。

## 构建

需要 macOS 12 或更高版本、Python 3 和 Xcode Command Line Tools：

```bash
xcode-select --install
make build
```

输出应用：`build/Daily Wallpaper.app`。可以直接在 Finder 中双击，也可以运行：

```bash
open "build/Daily Wallpaper.app"
```

构建脚本生成当前 Mac 架构的可执行文件、多尺寸应用图标、Info.plist，并进行本地 ad-hoc 签名及验证。此产物用于本机运行；对外分发需要自己的 Developer ID 签名和 Apple 公证。

## 安装

执行以下命令安装应用：

```bash
make install
open "$HOME/Applications/Daily Wallpaper.app"
```

应用安装到当前用户的 `~/Applications`，也可以手动将构建好的应用拖到“应用程序”文件夹。更新时先通过菜单栏退出，再替换应用。

## 登录时启动

先将应用安装到固定位置，然后打开 **系统设置 → 通用 → 登录项**（部分系统版本显示为“登录项与扩展”），在“登录时打开”中添加 `Daily Wallpaper.app`。

每天的更新由应用管理。点击菜单中的“退出每日壁纸”后，本次登录期间停止运行，下次登录仍会按照登录项设置启动。

## 壁纸存储

原图、深色版及缓存保存在：

```text
~/Library/Application Support/DailyWallpaper/
```

## 验证和排查

```bash
make test
```

测试覆盖每日更新时间、深色图生成、原图保留、缓存读写、损坏图片拒绝、日期校验、重复照片识别及缓存缺失修复。

手动验证：双击应用后检查菜单栏图标；点击“关于”查看版本；切换系统浅色/深色外观，检查壁纸和菜单状态；检查睡眠唤醒、外接显示器及退出。部分桌面空间的设置可能需要切换到该空间后才生效。

需要查看控制台输出时，先退出应用，再从终端启动包内可执行文件：

```bash
"build/Daily Wallpaper.app/Contents/MacOS/DailyWallpaper"
```

## 数据来源

每日壁纸信息：[Bing Wallpaper API](https://bing.wdbyte.com/today)。图片版权归原作者及相关权利方所有，本工具仅供个人桌面壁纸使用。
