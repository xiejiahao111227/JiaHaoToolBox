# 嘉豪工具箱（JiaHaoToolBox）

一款面向 Android 设备的 ADB / Fastboot 刷机与设备管理工具箱。

**本项目是基于开源项目 [紫罗兰工具箱 / VioletToolBox](https://github.com/Smart-Paocai/VioletToolBox)（GPL-3.0，原作者 泡菜 / Smart-Paocai）修改而来的衍生版本。**

## 与上游的差异

本仓库不是一次简单改名。相对上游的具体修改如下：

| 项目 | 说明 |
| --- | --- |
| 品牌与产物 | 解决方案、工程、`AssemblyName` / `Product` / `Title` 全部改为 `JiaHaoToolBox`，产物为 `JiaHaoToolBox.exe`；子项目 `violet_payload` 改为 `jiahao_payload` |
| 应用数据目录 | 应用数据与日志前缀由 `VioletTool` 改为 `JiaHaoTool`，避免与原版共用同一目录互相覆盖状态 |
| 图标 | 移除上游 logo 美术资源，改为脚本生成的原创图标（`tools/make-icon.ps1` → `JiaHaoToolBox.ico`）。功能图标丢失的根因是 `images/` 下 63 个 SVG 用中文文件名，`SvgViewbox` 的相对 URI 在打包后解析不到：已全部改成 ASCII 名（对照表见 `tools/icon-rename-map.txt`），并补制 8 个上游缺失的图标（android / backup / baseband / cloud-download / douyin / flash-mem / snapdragon / telegram），XAML 引用同步更新 |
| 公告拉取 | 关闭。原实现从上游 `violettool.top/notice.json` 拉取公告并以本工具名义展示，分支不应冒名转发；接口保留，填入自建地址即可恢复（`MainWindow.BroadcastNotice.cs`），本地可用 `notice.json` 提供自己的公告 |
| 启动计数上报 | 移除。原实现每次启动向 `violettool.top/web-api/open-count/increment` POST 一次，会污染原作者的统计数据 |
| 关于页面 | 重写为来源归属 + 许可证说明；上游作者头像、收款码与 B 站 / 抖音 / Telegram 入口全部保留，但逐项标注"属于上游原作者，本修改版与其无隶属或背书关系"，并保留上游代码贡献者鸣谢与开源项目列表 |
| 上游多语 README | 删除 `docs/` 下六份翻译文档，其内容描述上游完整版功能集，与本仓库实际状态不符 |
| 版本号 | 徽章为 `正式版 V1.5`，其下是上游格式的机型版本串 `OS1.0.5.0.UMNMIXM`；程序集 `Version=1.5.0`、`InformationalVersion=1.5.0+OS1.0.5.0.UMNMIXM` |
| 主题色 | 由上游紫色系改为蓝色：主色 `#FF2E7CD6`、强调色 `#FF4A90E2`，其余紫/品红按 HSL 色相旋转到 200°–230° 区间，明度与透明度保持不变（涉及 `MainWindow.xaml` / `Window1.xaml` / `HorizontalBattery.xaml` / `App.xaml` 与 `HorizontalBattery.xaml.cs`，共 130 余处色值） |
| 版本号徽章点击 | 原实现点击徽章打开上游 QQ 群分享页（`JoinQQGroupButton_Click`），已改为跳转本工具「关于」页（`VersionBadgeButton_Click`），控件更名为 `VersionBadgeButton`，`oujiaflash.cs` 刷写日志里的版本取值同步改名。本仓库不再有任何指向上游 QQ 群的入口 |
| 侧边栏导航 | `hc:SideMenu` 的 `ExpandMode` 由 `Freedom` 改为 `ShowAll` 并常驻展开（配 `NavTopItemStyle` / `NavLeafItemStyle` 收紧行高，22 行一屏显示）。上游分组折叠依赖 `SideMenuItem.IsSelected`，启动时只有一处伪造点击展开"刷写功能"，其余分组永远点不开；同时删除三段绑定到 HandyControl 3.5.1 中并不存在的 `IsExpanded` 的箭头触发器 |
| 安装包 | 新增 WiX MSI 与 Inno Setup EXE 两套每用户安装包，见「打包」 |
| 启动耗时 | 图标改为构建期预转换的矢量资源，并去掉启动遮罩里的人为等待，冷启动约 4.1 秒降到 1.5 秒，见「图标与启动性能」 |

## 功能范围

上游约 110 项功能在本仓库中全部保留代码并开放入口，侧边栏共 18 个页面：

- **主页** — 设备状态识别、重启到 Fastboot / Recovery、槽位切换、无线调试
- **投屏** — scrcpy 投屏、电源键 / 息屏 / 亮屏、自定义分辨率
- **基本刷入** — `boot` / `init_boot` 等镜像刷入、解锁与回锁、设备格式化、FRP 擦除
- **可视刷写** — ADB 与 Fastboot 下读取分区表，分区可视化读 / 写 / 擦，GPT 回读与刷写，手敲 Fastboot 命令
- **欧加线刷** — 欧加机型线刷包解包与刷入
- **EDL 刷写** — 9008 分区读写，分区全选、分区搜索、设备管理器入口
- **降级助手** — ColorOS 降级流程辅助
- **模块专区** — 隐藏环境 / 模块管理
- **断点续传** — aria2c 断点续传下载
- **文件传输** — 设备与电脑间文件推拉
- **脱机修补** — Magisk 脱机修补（含保留 AVB2.0/dm-verity、安装到 Recovery、自动识别 KMI、自动刷入并安装 APK 等高级选项）
- **应用管理** — 应用列表、冻结 / 解冻、APK 提取与卸载
- **安卓通用** — 通用安卓工具集
- **Payload** — `payload.bin` 解包
- **备份助手** — 分区与数据备份
- **下载专区** — 磁贴式资源目录，含常用驱动直链（安卓通用 / MTK / 高通 / LibUSB / OPPO）
- **Rom专区** — 镜像下载、Rom 获取（含 C16 动态解析开关）、联想查包
- **关于**

> 这些模块靠 `FindName` 与编译期字段被大量引用，直接从 XAML 删除节点会导致 CS0103 编译错误；开放入口只需要处理 `SideMenuItem` 与页面 `Visibility`。

## 依赖上游服务器的功能

以下代码路径仍指向原作者的基础设施。它们功能可用，但**数据与流量都落在第三方服务器上**，二次分发前建议自建服务并替换常量：

- `MainWindow.xaml.cs` — 下载专区驱动 / Root 管理器 / ROM 资源列表（`gitee.com/smartpaocai/smart-tool`，磁贴需**双击**进入子列表）
- `RomDownload.cs` — Rom 专区后端 `violettool.top/rom-api`
- `MainWindow.EdlFlash.cs` — EDL 云端 Firehose 包与工单上传
- `MainWindow.OnePlusAutoRoot.cs` — 自动 Root 所需 APK 下载

公告接口与启动计数上报已按上表说明关闭，不会请求上游。

## 构建

开发环境：Windows 10 / 11，.NET 8 SDK 或更高版本。

```powershell
dotnet restore JiaHaoToolBox/JiaHaoToolBox.csproj
dotnet build JiaHaoToolBox/JiaHaoToolBox.csproj -c Debug
```

发布 x64 桌面版本（安装包用的就是这条命令的产物）：

```powershell
dotnet publish JiaHaoToolBox/JiaHaoToolBox.csproj -c Release -r win-x64 --self-contained true -o publish
```

程序运行依赖 `platform-tools`（adb / fastboot）、`scrcpy`、`7z.exe` 等外部工具，需随发布包一并放置到输出目录，不能只分发 EXE。

### platform-tools（检测设备的前提）

工具箱按 `GetToolPath()`（`MainWindow.xaml.cs`）的顺序找 adb：`<程序目录>\platform-tools\adb.exe` → 上级目录 → 解决方案根 → 系统 PATH → `%LOCALAPPDATA%\Android\Sdk\platform-tools`。**一个都找不到时，设备检测会静默返回"未连接"而不报错**（`MainWindow.xaml.cs` 里 adb 与 fastboot 双双缺失即 `return`），看起来就像"检测不到手机"。

执行 `bash tools/get-platform-tools.sh` 从 `dl.google.com` 拉取官方 platform-tools 并解压到 `publish/platform-tools`；`tools/build-setup.sh` 会在 `dotnet publish` 之后检查该目录，缺失则自动执行下载，因此两种安装包都自带 adb / fastboot。platform-tools 是 Google 的 Apache-2.0 二进制，不入库（`publish/` 已在 `.gitignore`），随包保留其 `NOTICE.txt`。

投屏（`platform-tools/scrcpy.exe`）、解包（`7z.exe`）、断点续传（`aria2c.exe`）、EDL（`fh_loader.exe` / `QSaharaServer.exe`）等仍是各自独立项目的产物，需要自行放到上述目录，安装包里不含。

## 图标与启动性能

上游把 121 处图标写成 `<svg:SvgViewbox Source="images/xxx.svg">`。SharpVectors 是**每个实例**各自解析一遍 SVG 再重建绘图对象，而这些实例全部在 `InitializeComponent()` 里构造，于是窗口出现之前要先花约 1.9 秒处理图标——实测冷启动 4.1 秒，其中 `InitializeComponent` 占 2.97 秒。

本仓库改为构建期预转换：

1. `dotnet run --project tools/IconGen/IconGen.csproj -- <工程目录>` 用 SharpVectors 把 `images/*.svg` 转成冻结的 `DrawingImage`，坐标保留 2 位小数，输出 `JiaHaoToolBox/Icons.xaml`（约 128 KB）与 `tools/icon-manifest.tsv`；内嵌 base64 位图的 SVG（`coloros` / `image-file`）单独导出 PNG 并生成 `BitmapImage` 资源。
2. `bash tools/ps-enc.sh tools/xaml-svg-to-image.ps1 '$PSScriptRoot="<仓库绝对路径>/tools"'` 依据清单把 `MainWindow.xaml` / `Window1.xaml` 里的 `SvgViewbox` 换成 `<Image Source="{StaticResource ic_xxx}">`，并同步改写 `<Image.Style>` 与样式 `TargetType`。
3. `App.xaml` 的 `MergedDictionaries` 首位引入 `Icons.xaml`。

新增图标时把 SVG 放进 `images/`，重跑第 1 步，再按同样的 `<Image Source="{StaticResource ic_文件名}">` 写法引用。

SharpVectors 依赖仍保留，因为还有两类图标必须在运行时解析：驱动列表模板里 `Source="{Binding IconSource}"` 绑定的是 SVG 路径字符串，以及 `MainWindow.xaml.cs` / `oujiaflash.cs` 中动态 `new SvgViewbox{...}` 创建的投屏控制条与文件夹按钮。

另外删除了 `MainWindow_Loaded` 里 `Task.Delay(350)` + `Task.Delay(100)` 两段"等 UI 稳定"的假等待，遮罩改为在首次布局完成时即隐藏。优化后 `InitializeComponent` 约 0.64 秒，端到端可用约 1.4–1.7 秒（`tools/startup-timing.ps1 -Exe <产物路径> -MarkerFile tools/overlay-marker.txt` 可复测）。

## 打包

`bash tools/build-setup.sh` 一次产出两种安装包（版本号 1.5.0，均装在 `%LOCALAPPDATA%\Programs\JiaHaoToolBox`，均自带 platform-tools）：

| 产物 | 工具 | 说明 |
| --- | --- | --- |
| `out/JiaHaoToolBox-Setup-1.5.0.msi` | WiX 5.0.2 + `WixToolset.UI.wixext` | `setup/setup.wxs` + 由 `tools/harvest-publish.ps1` 依据 `publish/` 生成的 `setup/files.wxs`；`Scope=perUser`、`Language=2052`、含开始菜单与桌面快捷方式 |
| `out/JiaHaoToolBox-Setup-1.5.0.exe` | Inno Setup 6 | `setup/JiaHaoToolBox.iss`，`PrivilegesRequired=lowest` |

两者的许可证页面都用 `setup/license.rtf`（由 `tools/make-license-rtf.ps1` 从 `LICENSE` 生成，纯 ASCII 以免 RTF 编码错乱）。

> 受限环境下 MSI 可能报 `Error 2502 / 2503`：这是 Windows Installer 写 `C:\WINDOWS\Installer\inprogressinstallinfo.ipi` 需要提权，与安装包本身无关。用管理员命令行安装，或直接用 Inno Setup 的 EXE。


## 许可证

GPL-3.0-or-later。本仓库以 GPL-3.0 分发，`LICENSE` 为原文未改动。

作为 GPL 衍生作品，再分发时必须：

1. 保留本 `LICENSE` 文件与上游版权声明；
2. 保留本 README 中指向 VioletToolBox 项目的来源归属；
3. 以同一许可证公开全部修改后的源代码；
4. 分发二进制时随附对应源码或明确的源码获取方式。

原作者 泡菜（Smart-Paocai）对其原始作品保有的权利不受本修改版影响；"紫罗兰工具箱 / VioletToolBox" 名称与标识归原作者所有，本修改版与之无隶属或背书关系。
