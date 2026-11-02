# TalkMate

> 用口语对话练英语的本地优先 Web App：按一下麦克风开口说，语音识别 → 大模型短回复 → 语音播报；支持自由闲聊、看图说话、生活情景、角色对话和分幕讲故事。

当前版本：**1.0** · 许可证：[MIT](LICENSE)

## 特性

- **四种练习模式**：Chat（自由对话）、Scene（看图说话 / 生活情景）、Role（角色与导师）、Story（童话寓言分幕讲述）。每个模式独立保存对话，切换不串台。
- **两种人设**：Buddy（朋友式陪聊，1–3 句）与 Coach（轻纠错 + `**生词**` / `==地道表达==` 高亮）。
- **本机语音栈**：faster-whisper `small`（端口 8787，OpenAI 兼容转写）+ Kokoro-82M ONNX（端口 8788，八档音色）。TTS 的 `auto` 顺序是 edge-tts → Kokoro → Windows SAPI，断网时会落到本地权重。
- **手机可用**：同一 Wi-Fi 打开启动窗口里的局域网地址，语音服务地址会自动跟随页面主机名。
- **可控成本与隐私**：API Key 只存本机浏览器；录音只发往你选择的 ASR；未配置 Key 时进入演示回复，不假装联网成功。
- **轻量记录**：本地历史、英文词数 / 练习时长统计与约 6 个月热力图。
- **无前端构建**：单个 `index.html`（原生 HTML/CSS/JS）+ Python 服务。

## 快速开始（源码）

需要 Windows + Python 3.10+。脚本是 PowerShell / `.bat`；Python 服务本身跨平台。

1. 安装 [Python 3.10+](https://www.python.org/downloads/)，安装时勾选 **Add python.exe to PATH**。
2. 双击 `01-First-Install.bat`：创建 `.venv-whisper` / `.venv-tts`、安装依赖；Kokoro 权重（约 337 MB）会自动下载并校验 SHA-256。
3. 双击 `02-Start-TalkMate.bat`：启动网页（8080）、Whisper（8787）、TTS（8788），并打开浏览器。首次语音识别会下载 faster-whisper `small` 权重（约 460 MB，只需一次）。
4. 在「设置」里填入 DeepSeek API Key（Base URL 默认 `https://api.deepseek.com`），点「测大模型」。
5. 停止服务：双击 `03-Stop-TalkMate.bat`。

> 仓库**不含模型权重**：`scripts/models/` 已被 `.gitignore` 排除（单文件超过 GitHub 限制，仓库也应保持轻量）。权重由安装脚本或首次运行自动获取。

手机：与电脑连同一 Wi-Fi，打开启动窗口打印的 `http://<本机IP>:8080/`（`02` 默认开启局域网绑定）。

## 便携包（含模型）

```powershell
powershell -ExecutionPolicy Bypass -File scripts\build-package.ps1
```

生成 `TalkMate-Portable.zip`（约 750 MB，内含 Whisper 与 Kokoro 权重），目标机只需 Python。打包前会自动校验并同步 `index.html` 里的内嵌部署脚本。分步图文说明见 [README-使用说明.md](README-使用说明.md)。

## 目录

```
index.html                  单页 App：界面、会话、设置、部署脚本内嵌副本
scripts/
  local_whisper_server.py   faster-whisper ASR（OpenAI 兼容）
  local_tts_server.py       Kokoro / edge-tts / SAPI TTS
  _static_app.py            静态页面服务（ThreadingHTTPServer）
  start-all.ps1             启动全部服务
  stop-all.ps1              停止 App / Whisper / TTS
  setup-first-run.ps1       首次安装
  deploy-local-whisper.ps1  单独部署 ASR
  deploy-local-tts.ps1      单独部署 TTS
  download_kokoro_models.py Kokoro 权重下载（固定 release + SHA-256）
  build-package.ps1         生成便携包
  sync-embeds.ps1           同步 index.html 内嵌脚本
tests/                      Node 测试
assets/scenes/              场景练习图片
PRD.md                      产品需求文档
README-使用说明.md           安装与使用手册
```

## 开发

```bash
npm test        # 纯函数、内联脚本语法、内嵌块与源文件一致性
```

修改 `scripts/` 里的服务或部署脚本后，运行 `scripts\sync-embeds.ps1` 把内容同步进 `index.html`；`-Check` 只校验，漂移时返回 1。

端口与绑定由环境变量控制：`TALKMATE_HOST`（默认 `127.0.0.1`）、`TALKMATE_APP_PORT`（8080）、`TALKMATE_WHISPER_PORT`（8787）、`TALKMATE_TTS_PORT`（8788）。

## 隐私与安全

- API Key 保存在浏览器 `localStorage`，只发往你配置的 Base URL。
- 上传的照片只作为当前模式的对话上下文，刷新即失效，不写入本地存储。
- 本地 Whisper/TTS 会校验写请求的 `Origin`（仅本机与局域网页面）。同网设备只要能打开 App 页面仍可使用这些端口；把网络借给别人前请先停止服务。

## 已知限制

- 安装 / 启动 / 打包脚本面向 Windows，其他平台未覆盖。
- 浏览器语音识别（Web Speech）的质量因浏览器和机型而异，建议优先使用本地 Whisper。
- `index.html` 约 220 KB（含内嵌部署脚本），单文件是刻意的取舍，没有前端构建链。

## 许可证

[MIT](LICENSE) © 2026 steveeyre
