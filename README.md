# Daily Bing Wallpaper for macOS

每天从 [Bing Wallpaper API](https://bing.wdbyte.com/today) 获取今日壁纸，并自动设置为 macOS 桌面背景。

## 环境要求

- macOS
- Xcode Command Line Tools
- Swift 5.5 或更高版本

安装编译工具：

```bash
xcode-select --install
```

## 编译

项目中包含 `DailyWallpaper.swift`，执行：

```bash
mkdir -p "$HOME/.local/bin"

swiftc -parse-as-library \
  DailyWallpaper.swift \
  -framework AppKit \
  -o "$HOME/.local/bin/daily-wallpaper"
```

## 手动运行

```bash
"$HOME/.local/bin/daily-wallpaper"
```

壁纸会保存到：

```text
~/Library/Application Support/DailyWallpaper/
```

## 设置每日自动运行

创建文件：

```text
~/Library/LaunchAgents/com.example.daily-wallpaper.plist
```

内容如下，将 `/Users/你的用户名` 替换为实际用户目录：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">

<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.example.daily-wallpaper</string>

    <key>ProgramArguments</key>
    <array>
        <string>/Users/你的用户名/.local/bin/daily-wallpaper</string>
    </array>

    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>9</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>

    <key>RunAtLoad</key>
    <true/>

    <key>StandardOutPath</key>
    <string>/Users/你的用户名/Library/Logs/daily-wallpaper.log</string>

    <key>StandardErrorPath</key>
    <string>/Users/你的用户名/Library/Logs/daily-wallpaper-error.log</string>
</dict>
</plist>
```

加载定时任务：

```bash
launchctl bootstrap \
  "gui/$(id -u)" \
  "$HOME/Library/LaunchAgents/com.example.daily-wallpaper.plist"
```

立即测试：

```bash
launchctl kickstart -k \
  "gui/$(id -u)/com.example.daily-wallpaper"
```

## 卸载定时任务

```bash
launchctl bootout \
  "gui/$(id -u)" \
  "$HOME/Library/LaunchAgents/com.example.daily-wallpaper.plist"
```

## 查看日志

```bash
tail -f "$HOME/Library/Logs/daily-wallpaper.log"
```

错误日志：

```bash
tail -f "$HOME/Library/Logs/daily-wallpaper-error.log"
```

## 数据来源

每日壁纸信息由以下接口提供：

```text
https://bing.wdbyte.com/today
```

图片版权归原作者及相关权利方所有，本工具仅供个人桌面壁纸使用。
