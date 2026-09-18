# 嘉豪工具箱（JiaHaoToolBox）

一款面向 Android 设备的 ADB / Fastboot 刷机与设备管理工具箱。

**本项目是基于开源项目 [紫罗兰工具箱 / VioletToolBox](https://github.com/Smart-Paocai/VioletToolBox)（GPL-3.0，原作者 泡菜 / Smart-Paocai）修改而来的衍生版本。**

## 与上游的差异

本仓库不是一次简单改名。相对上游的具体修改如下：

| 项目 | 说明 |
| --- | --- |
| 品牌与产物 | 解决方案、工程、`AssemblyName` / `Product` / `Title` 全部改为 `JiaHaoToolBox`，产物为 `JiaHaoToolBox.exe`；子项目 `violet_payload` 改为 `jiahao_payload` |
| 应用数据目录 | 应用数据与日志前缀由 `VioletTool` 改为 `JiaHaoTool`，避免与原版共用同一目录互相覆盖状态 |
| 图标 | 移除上游 logo 美术资源，改为脚本生成的原创图标（`tools/make-icon.ps1` → `JiaHaoToolBox.ico`） |
| 公告拉取 | 关闭。原实现从上游 `violettool.top/notice.json` 拉取公告并以本工具名义展示，分支不应冒名转发；接口保留，填入自建地址即可恢复（`MainWindow.BroadcastNotice.cs`） |
| 启动计数上报 | 移除。原实现每次启动向 `violettool.top/web-api/open-count/increment` POST 一次，会污染原作者的统计数据 |
| 关于页面 | 重写为来源归属 + 许可证说明，移除原作者个人头像、支付宝/微信收款码、抖音/Telegram/B 站等个人账号入口与 contributors 个人照片 |
| 上游多语 README | 删除 `docs/` 下六份翻译文档，其内容描述上游完整版功能集，与本仓库实际状态不符 |

功能入口收敛见下节。

## 首版功能范围

上游约 110 项功能，本仓库首版只开放与刷机、设备管理直接相关的模块：

- **主页** — 设备状态识别、重启到 Fastboot / Recovery、槽位切换、无线调试
- **基本刷入** — `boot` / `init_boot` 等镜像刷入、解锁与回锁、设备格式化、FRP 擦除
- **可视刷写** — ADB 与 Fastboot 下读取分区表，分区可视化读 / 写 / 擦，GPT 回读与刷写
- **应用管理** — 应用列表、冻结 / 解冻、APK 提取与卸载
- **关于**

其余模块（EDL 刷写、欧加线刷、降级助手、模块专区、断点续传、文件传输、脱机修补、安卓通用、Payload、备份助手、下载专区、ROM 专区、投屏）的**代码完整保留且参与编译**，仅在侧边栏以 `Visibility="Collapsed"` 收起、不提供入口。

> 注意：这些模块靠 `FindName` 与编译期字段被大量引用，直接从 XAML 删除节点会导致 CS0103 编译错误。若后续要开放某个模块，只需把对应 `SideMenuItem` 的 `Visibility` 去掉，不需要改动其它代码。

## 依赖上游服务器的功能

以下代码路径仍指向原作者的服务器。它们在首版中已被收起，但**若将来开放，需要先自建对应服务并替换常量**，否则会依赖他人基础设施：

- `MainWindow.xaml.cs` — 驱动 / Root 管理器 / ROM 资源列表（`gitee.com/smartpaocai/smart-tool`）
- `RomDownload.cs` — ROM 专区后端 `violettool.top/rom-api`
- `MainWindow.EdlFlash.cs` — EDL 云端 Firehose 包与工单上传
- `MainWindow.OnePlusAutoRoot.cs` — 自动 Root 所需 APK 下载

## 构建

开发环境：Windows 10 / 11，.NET 8 SDK 或更高版本。

```powershell
dotnet restore JiaHaoToolBox/JiaHaoToolBox.csproj
dotnet build JiaHaoToolBox/JiaHaoToolBox.csproj -c Debug
```

发布 x64 桌面版本：

```powershell
dotnet publish JiaHaoToolBox/JiaHaoToolBox.csproj -c Release -r win-x64 --self-contained false
```

程序运行依赖 `platform-tools`（adb / fastboot）、`scrcpy`、`7z.exe` 等外部工具，需随发布包一并放置到输出目录，不能只分发 EXE。

## 许可证

GPL-3.0-or-later。本仓库以 GPL-3.0 分发，`LICENSE` 为原文未改动。

作为 GPL 衍生作品，再分发时必须：

1. 保留本 `LICENSE` 文件与上游版权声明；
2. 保留本 README 中指向 VioletToolBox 项目的来源归属；
3. 以同一许可证公开全部修改后的源代码；
4. 分发二进制时随附对应源码或明确的源码获取方式。

原作者 泡菜（Smart-Paocai）对其原始作品保有的权利不受本修改版影响；"紫罗兰工具箱 / VioletToolBox" 名称与标识归原作者所有，本修改版与之无隶属或背书关系。
