# 奶蛙动作增强版：构建与验收

## 本轮改动范围

- `running-right`（第 1 行）：向右移动时从尾部产生黄绿色屁雾。
- `running-left`（第 2 行）：向左移动时从尾部产生黄绿色屁雾。
- `waiting`（第 6 行）：保留等待输入触发逻辑，视觉替换为完整 8 帧敲键盘。
- `jumping`（第 4 行）：受保护；奶蛙悬浮时使用同一行的 `jumping-loop` 状态，让捧腹大笑与本地笑声一起持续循环。
- `running`（第 7 行）：奶蛙开发版不再显示原手部犹豫画面；纯思考时改为第 11 行 `typing`。
- `idle`、`waving`、`failed`、`review` 和注视方向：本轮受保护。

原版 Codex 将纯推理映射到 `running`。本扩展仅对奶蛙开发版把 `running` 和真实工具执行统一显示为 `typing`，从而完整替换原手部犹豫画面。

## 工具执行敲键盘扩展

宿主扩展代码仍然区分两类运行阶段，但奶蛙开发版现在都显示敲键盘：

- 纯推理、组织下一步：当宿主状态为 `running` 时切换到第 11 行 `typing`。
- `commandExecution`、`fileChange`、`mcpToolCall` 或 `webSearch` 处于 `inProgress`：同样切换到 `typing`。

扩展精灵图在原 11 行下方新增第 12 行 `typing`，共 8 帧，清单声明 `spriteVersionNumber: 3`。宿主补丁同时扩展自定义宠物扫描器，使版本 3 接受 1536×2496 精灵图；否则该宠物会在进入设置列表前被过滤。加载器实际使用目录生成的 `custom:naifrog-dev`，补丁同时兼容历史逻辑 ID `nailong-dev`。奶蛙开发版在渲染时使用 12 行布局，其他内置或自定义宠物仍使用原布局。拖动和悬浮产生的临时状态继续覆盖 `typing`，结束后再恢复当前任务状态。

小型桌面键盘素材已生成并完成透明化处理；开发版精灵图已扩展为 12 行。重新构建时使用：

当前 12 行宠物资源和宿主补丁均已安装；以下命令用于后续重建与复验。

```powershell
python .\tools\prepare_gpt_grid.py .\assets\gpt-originals\typing-gpt.png .\assets\prepared\typing.png --columns 4 --rows 2

powershell -ExecutionPolicy Bypass -File .\tools\build_test_spritesheet.ps1 `
  -RunningRightGrid .\assets\prepared\running-right.png `
  -RunningLeftGrid .\assets\prepared\running-left.png `
  -TypingGrid .\assets\prepared\typing.png

python .\tools\validate_pet.py .\naifrog-dev `
  --baseline .\naifrog\spritesheet.webp `
  --allowed-rows 1,2,6,11 `
  --require-changed-rows 1,2,6,11
```

## GPT 网页图片预处理

用户提供的原始生成图保存在 `assets/gpt-originals`，不做覆盖。网页生成图带有画面内棋盘格且尺寸不固定，使用以下脚本恢复透明通道并归一化为 192×208 单帧：

```powershell
python .\tools\prepare_gpt_grid.py .\assets\gpt-originals\running-right-gpt.png .\assets\prepared\running-right.png --columns 4 --rows 2
python .\tools\prepare_gpt_grid.py .\assets\gpt-originals\waiting-gpt.png .\assets\prepared\waiting.png --columns 3 --rows 2
python .\tools\prepare_gpt_grid.py .\assets\gpt-originals\running-left-gpt.png .\assets\prepared\running-left.png --columns 4 --rows 2
python .\tools\prepare_gpt_grid.py .\assets\gpt-originals\typing-gpt.png .\assets\prepared\typing.png --columns 4 --rows 2
```

当前 `waiting-gpt.png` 仅作为历史素材保留，不再进入最终精灵图。`tools/build_test_spritesheet.ps1` 将敲键盘 8 帧同时装入第 6 行和第 11 行。

## 悬浮笑声音频

- 本地资源：`assets/audio/nailong-laugh.mp3`
- SHA-256：`8ECA7301D51A23E26526EF352A83B63E954F69C70DF342854AC37113C3BC49E9`
- MP3 时长：约 14.81 秒；打包进 ASAR 后从本地资源加载，不依赖运行时网络。
- 仅 `nailong-dev`（真实加载 ID 为 `custom:naifrog-dev`）播放；音量 65%，悬浮期间循环。
- 离开奶蛙、开始拖动、指针取消、宠物切换或组件卸载时暂停并归零。

## 自动验收

构建后运行：

```powershell
python .\tools\validate_pet.py .\naifrog-dev `
  --baseline .\naifrog\spritesheet.webp `
  --allowed-rows 1,2,6 `
  --require-changed-rows 1,2,6
```

验收必须显示 `VALIDATION=PASS`。第 1、2、6 行的 `changed_pixels` 必须大于 0，其余行必须等于 0。

## 安装测试宠物

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\install_test_pet.ps1
```

然后在 Codex 中进入：

```text
Settings -> Pets -> Custom pets -> Refresh -> 奶蛙开发版
```

开发版清单使用逻辑 ID `nailong-dev`，Codex 自定义宠物加载器实际生成运行 ID `custom:naifrog-dev`；两者均由宿主补丁兼容，不会覆盖正式奶蛙。

## Codex 宿主交互修复

仅替换精灵图不能解决宿主窗口“捕获到拖动但不移动”的问题。本项目因此为 `nailong-dev` / `custom:naifrog-dev` 增加一组定向宿主补丁：

- 拖动时强制使用 Codex 现有的渲染器坐标移动路径，绕过失效的原生窗口拖动。
- 奶蛙命中区域的上边、左右位置和宽度保持原增强版不变（左右各 12 CSS px）；仅将下边再向下延长 48 CSS px，形成竖向长方形。该判断使用真实运行 ID `custom:naifrog-dev`；角色用顶部 12 px 内边距锚定，显示尺寸和位置不变。
- 悬浮时 `jumping-loop` 优先于宿主原生的普通 `jumping`；开始拖动会先清除悬浮标志，因此拖动状态仍然优先。
- 不改变单击逻辑，也不改变其他宠物的拖动或悬浮逻辑。

先做只读构建验证：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\patch-codex-pet-interactions-msix.ps1 `
  -OutputRoot .\work\pet-host-msix
```

确认 dry run 通过后，再安装并启动补丁版 Codex：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\patch-codex-pet-interactions-msix.ps1 `
  -Install -Launch -InstallPrerequisites `
  -OutputRoot .\work\pet-host-msix
```

脚本不会直接修改 `C:\Program Files\WindowsApps` 中的文件，而是复制、补丁、重新打包并签名安装。Microsoft Store 更新 Codex 后需要针对新版本重新执行；应始终先运行 dry run。

## 人工验收清单

1. 静置 20 秒：待机、眨眼和注视方向没有异常。
2. 鼠标悬浮：角色左右边缘外约 12 px、原命中框下边再向下约 48 px 均能触发；保持悬浮时捧腹大笑与笑声持续循环，移开后同时停止。
3. 单击：仍然不触发新动作。
4. 向右拖动：屁雾从尾部向左后方拖出，不遮挡脸和肚皮。
5. 向左拖动：屁雾从尾部向右后方拖出，方向与运动相反。
6. 让 Codex 进行纯思考或执行工具：原手部犹豫不再出现，改为小型桌面键盘动画。
7. 完成任务：原完成动画保持不变。
8. 制造一个可恢复的失败/阻塞场景：原失败动画保持不变。
9. 检查边缘：透明背景没有黑框、紫边、绿色矩形或相邻帧串色。
10. 连续拖动 10 次：动画流畅，没有尺寸跳变或角色抖动。
