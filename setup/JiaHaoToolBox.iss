; 嘉豪工具箱 安装包脚本（Inno Setup 6）
; 编译："%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe" setup\JiaHaoToolBox.iss
; 与 WiX 版 MSI 的区别：PrivilegesRequired=lowest，全程不碰 C:\WINDOWS\Installer，
; 在本机这种受限的管理员令牌下也能直接双击安装。
#define MyAppName "嘉豪工具箱"
#define MyAppVersion "1.6.1"
#define MyAppExeName "JiaHaoToolBox.exe"

[Setup]
AppId={{7F3D1C94-2B6E-4A58-9C07-D5E8A1F4B620}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} 正式版 V1.6.1 (OS1.0.6.1.UMNMIXM)
AppPublisher={#MyAppName}
AppPublisherURL=https://github.com/Smart-Paocai/VioletToolBox
AppSupportURL=https://github.com/Smart-Paocai/VioletToolBox
AppUpdatesURL=https://github.com/Smart-Paocai/VioletToolBox
DefaultDirName={localappdata}\Programs\JiaHaoToolBox
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
ShowLanguageDialog=no
LicenseFile=license.rtf
OutputDir=..\out
OutputBaseFilename=JiaHaoToolBox-Setup-{#MyAppVersion}
SetupIconFile=..\JiaHaoToolBox\JiaHaoToolBox.ico
VersionInfoVersion=1.6.1
VersionInfoProductVersion=1.6.1
Compression=lzma2/max
SolidCompression=yes
LZMAUseSeparateProcess=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
UninstallDisplayName={#MyAppName}
UninstallDisplayIcon={app}\{#MyAppExeName}
MinVersion=6.1sp1

[Languages]
; 安装向导必须是中文：Inno Setup 只自带英文 Default.isl，简体中文是官方翻译（6.5.0+ 消息集），
; 随仓库一起放进来，免得换台机器打包就得去 jrsoftware.org 现下。
; 只挂一种语言时 Inno 不会再弹语言选择框，ShowLanguageDialog=no 只是把这件事写死。
Name: "chinesesimplified"; MessagesFile: "languages\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\publish\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Comment: "正式版 V1.6.1 / OS1.0.6.1.UMNMIXM"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; WorkingDir: "{app}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}"
