<div align="center">

# Codex 奶蛙桌宠增强版

**简体中文 · [English](./README.en.md)**

在 [timerring/codex-pet-naiwa](https://github.com/timerring/codex-pet-naiwa) 基础上进行的 Windows Codex Desktop 深度增强版。

</div>

## 功能

- Codex 思考、执行命令或调用工具时，奶蛙使用小型桌面键盘敲键盘。
- 鼠标悬浮时持续循环捧腹大笑，并循环播放本地笑声音频；移开后立即停止。
- 悬浮命中区域在保持上边和宽度不变的情况下向下扩展，更容易触发。
- 左右拖动时播放对应走路动作，尾部向运动反方向喷出黄绿色屁雾。
- 保留待机、注视、完成、失败和单击不触发额外动作等原有行为。
- 笑声音频随项目本地打包，不需要 OpenAI API Key，也不依赖运行时网络播放。

## 兼容性与重要说明

仓库包含两种使用方式：

1. `naifrog/`：上游标准自定义宠物，复制到 Codex 宠物目录即可使用。
2. `naifrog-dev/`：本仓库增强版资源，需要同时应用 `tools/patch-codex-pet-interactions-msix.ps1` 中的 Windows Codex Desktop 宿主补丁。

增强功能目前在以下环境完成验证：

- Windows 10/11
- Codex Desktop `26.715.7063.0`
- PowerShell 5.1 或更高版本
- Node.js 与 Python 3

宿主补丁会验证当前 Codex 包中的精确代码标记；遇到不兼容的新版本会停止，不会盲目替换。Microsoft Store 更新 Codex 后，应重新执行 dry run。增强补丁只适用于 Windows MSIX，不适用于 macOS。

## 快速安装增强版

### 1. 克隆仓库

```powershell
git clone https://github.com/Lurek-st/codex-pet-naiwa-enhanced.git
Set-Location .\codex-pet-naiwa-enhanced
```

### 2. 安装奶蛙开发版资源

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\install_test_pet.ps1
```

在 Codex 中进入 **Settings → Pets → Custom pets → Refresh**，选择“奶蛙开发版”。

### 3. 先执行宿主补丁 dry run

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\patch-codex-pet-interactions-msix.ps1 `
  -DryRun `
  -OutputRoot "D:\CodexPetBuild"
```

只有日志明确显示 dry run 通过后，才继续安装。

### 4. 从独立 PowerShell 安装并重启 Codex

不要从即将被替换的 Codex 内置终端启动安装。请打开独立的 Windows PowerShell，进入仓库目录后运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\patch-codex-pet-interactions-msix.ps1 `
  -Install -Launch -InstallPrerequisites `
  -OutputRoot "D:\CodexPetBuild"
```

脚本会复制当前 Codex 包、提取并验证 ASAR、应用定向补丁、重新打包和签名，然后安装开发签名版本。它不会直接修改 `C:\Program Files\WindowsApps` 内的文件。安装期间 Codex 会关闭并重新启动。

## 只安装标准奶蛙

如果不需要敲键盘、悬浮笑声和拖动屁雾等宿主增强功能，只复制 `naifrog/` 即可：

```powershell
$codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME ".codex" }
$petDir = Join-Path $codexHome "pets\naifrog"
New-Item -ItemType Directory -Force $petDir | Out-Null
Copy-Item ".\naifrog\*" $petDir -Recurse -Force
```

然后在 Codex 的自定义宠物页面刷新并选择奶蛙。

## 验收

安装增强版后检查：

1. Codex 思考或执行工具时出现小型键盘动画，不再播放手部犹豫。
2. 鼠标放在奶蛙身体或下方扩展区域时开始大笑并播放笑声。
3. 保持悬浮至少 20 秒，大笑和笑声持续循环；移开后同时停止。
4. 向右拖动时屁雾向左后方喷出，向左拖动时屁雾向右后方喷出。
5. 单击不额外触发动作，其他原有状态保持正常。

完整开发、构建和人工验收说明见 [DEVELOPMENT.md](./DEVELOPMENT.md)。

## 开发验证

```powershell
python .\tools\validate_pet.py .\naifrog-dev `
  --baseline .\naifrog\spritesheet.webp `
  --allowed-rows 1,2,6,11 `
  --require-changed-rows 1,2,6,11

node --check .\tools\patch-codex-pet-interactions.cjs
```

验证结果应包含 `VALIDATION=PASS`。所有构建、解包、签名和测试输出都写入 `work/`，该目录已被 Git 忽略。

## 项目结构

```text
assets/                         原始和预处理动画素材、本地笑声音频
naifrog/                        上游标准奶蛙资源与预览
naifrog-dev/                    12 行增强版精灵图和清单
tools/                          构建、验证、安装与 MSIX 补丁脚本
DEVELOPMENT.md                  技术实现与完整验收说明
```

## 安全说明

- 仓库不包含 OpenAI API Key、GitHub Token、私钥或用户认证数据。
- 构建证书和生成的 MSIX 不会提交到源码仓库。
- 建议在运行安装脚本前阅读脚本，并始终先执行 dry run。
- 开发签名的 Codex 包可能被 Microsoft Store 后续更新替换，这是预期行为。

## Credits / 致谢

- 上游项目：[timerring/codex-pet-naiwa](https://github.com/timerring/codex-pet-naiwa)
- [Nitrogen216/awesome_pets](https://github.com/Nitrogen216/awesome_pets)
- [LynnShaw/naiwa-pet](https://github.com/LynnShaw/naiwa-pet)
- [Linux Do](https://linux.do/)

## 许可证

代码修改和本仓库原创内容使用 [MIT License](./LICENSE)。必须保留上游版权与许可证声明。Credits 中列出的第三方素材可能受其各自条款约束，不因本仓库的 MIT 许可证自动获得重新授权。
