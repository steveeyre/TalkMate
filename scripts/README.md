# TalkMate 本地语音部署与模型选型

> **本机已按「中档」落地（2026-09）**
> - ASR：faster-whisper **`small`** → `http://127.0.0.1:8787/v1`
> - TTS：**Kokoro-82M ONNX**（主）→ `http://127.0.0.1:8788/v1`（回退 edge-tts）
> - 手机同 Wi-Fi 请填：`http://<PC局域网IP>:8787/v1` / `:8788/v1`
> - 一键：`deploy-local-whisper.ps1 -Start -Model small` · `deploy-local-tts.ps1 -Start`
> - Kokoro 权重目录：`scripts/models/`（约 326MB + 28MB voices）

## 架构（手机也能用）

```
手机浏览器 App  ──HTTP(LAN)──►  PC 推理服务
   麦克风/扬声器                 faster-whisper / TTS
   UI + LLM API                  （本目录 scripts/）
```

- 手机负责：界面、录音上传、播放 AI 语音、调用云端大模型
- PC 负责：ASR / TTS 推理（可选）
- 手机访问 PC 时，设置里的地址请用 **局域网 IP**，例如：
  `http://192.168.x.x:8787/v1`（Whisper）、`http://192.168.x.x:8788/v1`（TTS）
- 不要只用 `127.0.0.1`——那是 PC 自己；手机连不上
- Windows 防火墙需放行 8787 / 8788（或专用网络）

## 当前默认选型评估

| 组件 | 当前 | 是否适合「手机客户端 + PC 服务」 | 说明 |
|------|------|----------------------------------|------|
| ASR | **faster-whisper**（默认 `base`） | **适合**（作为 PC 端服务） | CTranslate2，CPU 上快；**不能**指望在手机浏览器里直接跑大模型权重 |
| TTS | **edge-tts**（+ pyttsx3 回退） | **可用，但命名不严谨** | edge-tts 不是本地权重模型，而是微软神经 TTS 的本机代理，音质好、免费；pyttsx3 仅应急，**不建议**作为亲子英语主路径 |
| 手机端兜底 | Web Speech API + 系统 TTS | **适合，且延迟最低** | 无需 PC；准确度/音色因机型而异 |

**结论：**  
- 以「手机练口语、PC 出算力」为准：faster-whisper **选型正确**，应作为 PC 服务而不是手机端模型。  
- TTS 应明确拆成两套：**云端/代理神经 TTS（edge-tts）** 与 **真正的本地开源 TTS 权重**（见下表中/高档）。  
- 若目标是「手机上完全离线跑模型」，当前 Web 方案不够，需原生 App + whisper.cpp / 系统 TTS，那是另一条产品线。

---

## 低 / 中 / 高方案（为性能稍强的 PC）

参考配置：16 核 CPU + 集成显卡 + 32GB RAM 的轻薄本 → **轻松覆盖中档，高档也可尝试**。

### 低档 — 先跑通、手机延迟优先

| 项 | 选型 | 运行位置 | 说明 |
|----|------|----------|------|
| ASR 主路径 | **浏览器 Web Speech API** | 手机 | 零部署，亲子短句够用 |
| ASR 可选 | faster-whisper **`tiny`** | PC `:8787` | 体积小，CPU 秒回 |
| TTS 主路径 | **edge-tts**（现有 `:8788`） | PC 代理微软神经音 | 推荐 `female-youth` / `female-mid` |
| TTS 不推荐 | pyttsx3 / 系统 SAPI | 本机 | 仅断网应急 |
| 适用 | 任意能跑 Python 的 PC + 同一 Wi-Fi | | 模型下载 <100MB（tiny） |

启动：`scripts\deploy-local-whisper.ps1 -Start`（设 `TALKMATE_WHISPER_MODEL=tiny`）  
`scripts\deploy-local-tts.ps1 -Start`（当前 edge-tts 即低档 TTS 主力）

#
## TTS 音质选型（响应速度优先）

| 方案 | 音质 | 延迟 | 说明 |
|------|------|------|------|
| **edge-tts（当前默认优先）** | 最自然、少电子音 | 低（需联网） | 微软神经音；儿童女声 `en-US-AnaNeural` → 预设 **Female·Child** |
| **Kokoro-82M ONNX** | 良好，偶有合成感 | 很低（本地） | 离线/断网回退；`af_sky` 近似儿童女声 |
| Piper | 中等、偏机械 | 最低 | 纯 CPU 离线，不推荐主用 |
| StyleTTS2 / F5-TTS / CosyVoice | 更像真人 | 更高、部署重 | 升级方向，当前未内置 |

**默认音色：Female·Child**（向幼儿讲故事更贴）。

## 中档 — 日常主力（推荐默认）

| 项 | 选型 | 运行位置 | 说明 |
|----|------|----------|------|
| ASR | faster-whisper **`small`** 或 **`distil-small.en`** | PC `:8787` | 英语亲子对话性价比最高 |
| TTS | **Kokoro-82M**（`kokoro-v1.0` / `hexgrad/Kokoro-82M`） | PC `:8788` 独立服务 | 真正本地开源权重；英文音色多，适合讲故事 |
| 备选 TTS | **Piper** `en_US-lessac-medium` / `en_US-amy-medium` | PC | 比 edge-tts 更「真本地」，CPU 很快，音质中等 |
| LLM | 云端视觉模型（不变） | 云端 | 看图/故事理解仍走 API |
| 适用 | 8 核以上 / 16GB+，核显可加速 | | small 模型约 500MB 量级 |

环境变量示例：

```powershell
$env:TALKMATE_WHISPER_MODEL = "small"
# 或 distil-small.en（英语口语场景更省）
```

手机设置：

- Whisper Base URL：`http://<PC局域网IP>:8787/v1`
- TTS Base URL：`http://<PC局域网IP>:8788/v1`
- ASR 模式：本地 Whisper；TTS 模式：本地 TTS
- 音色：女·青年 / 女·中年（亲子）；讲故事可试儿童档

### 高档 — 故事朗读 / 播音感（性能稍强 PC）

| 项 | 选型 | 运行位置 | 说明 |
|----|------|----------|------|
| ASR | faster-whisper **`distil-large-v3`** 或 **`large-v3`** | PC `:8787` | 识别最稳；CPU 可用，有 iGPU/OpenVINO 更好 |
| ASR 备选 | whisper **`medium.en`** | PC | 英语专项，平衡延迟与精度 |
| TTS | **Kokoro**（较新权重，如 v1.1 系列）多音色 | PC | 开源里音质/速度比很好 |
| TTS 更高 | **StyleTTS2** 或 **XTTS-v2**（仅英文段落） | PC | 故事成段朗读更自然；占用更高，延迟更大 |
| 不推荐高档 | edge-tts 作为唯一 TTS | — | 音质可以，但依赖外网；高档应有本地权重兜底 |
| 适用 | 16 核 / 32GB，可开 Arc GPU 或大内存 CPU 推理 | | large-v3 权重约 3GB，首次下载久 |

```powershell
$env:TALKMATE_WHISPER_MODEL = "distil-large-v3"
# 或 large-v3
```

---

## 选型判断（是否「恰当」）

1. **faster-whisper：恰当**，前提是明确「装在 PC、手机当客户端」。默认 `base` 偏保守，亲子英语建议至少 **small**，要准确用 **distil-large-v3**。  
2. **「未命名 TTS」：应拆开说清**  
   - 现状=edge-tts **服务**（微软神经音色，经本机 API）→ 低档主力，**适合**  
   - 不是本地开源模型 → 中/高档应换成 **Kokoro / Piper / StyleTTS2** 等具名权重  
3. **手机「也能用」的正确含义**  
   - ✅ 手机浏览器 + 局域网访问 PC 服务（当前架构）  
   - ❌ 在手机浏览器里加载 large-whisper / 大 TTS（不现实）  
   - ✅ 无 PC 时：App 内 Web Speech + 系统 TTS（低档兜底）  
4. **16 核 + 32GB 的轻薄本**：直接按 **中档** 部署最合理；故事模式要更好听再上 **高档 Kokoro**。

## 建议默认组合（按你的使用场景）

| 场景 | ASR | TTS | 音色 |
|------|-----|-----|------|
| 日常亲子口语 | small（PC） | edge-tts 或 Kokoro | 女·青年 |
| 故事分幕练习 | small / distil-small.en | Kokoro（中高） | 女·中年 / 儿童档 |
| 无 PC 外出练 | 浏览器 Web Speech | 系统 TTS | 系统英文女声 |

## 与 App 的对应关系

- 设置 → ASR：浏览器本地 / **本地 Whisper** / 云端  
- 设置 → TTS：系统 / **本地 TTS** / 云端  
- 本地 Whisper 默认口：`8787`；本地 TTS 默认口：`8788`  
- 部署脚本：`deploy-local-whisper.ps1`、`deploy-local-tts.ps1`  
- 手机与 PC 需在同一局域网；首次启动 Whisper 会下载所选模型权重

## 开发与校验

- 网页服务：`scripts/_static_app.py` 由 `start-all.ps1` 直接启动，绑定地址/端口来自
  `TALKMATE_HOST` 与 `TALKMATE_APP_PORT`（默认 `127.0.0.1:8080`），不再每次生成。
- 安装脚本内嵌副本：改完 `local_*_server.py` / `deploy-*.ps1` 后运行
  `scripts\sync-embeds.ps1`，把内容同步进 `index.html`；`-Check` 只校验并在漂移时返回 1。
  `build-package.ps1` 打包前会自动执行一次。
- 测试：`npm test`（Node 内置 test runner）。覆盖纯函数、内联脚本语法、四个内嵌块与源文件一致。
- 模型权重（`scripts/models/`）与 `.venv-*` 不进 git，只随便携包分发。
- 停止服务：`scripts\stop-all.ps1`（或根目录 `03-Stop-TalkMate.bat`）。它只杀
  `start-all.ps1` 记录在 `%TEMP%\talkmate-pids\` 里、且命令行仍是本项目的进程；
  Ollama 不受影响。
- Whisper/TTS 只接受带本机或局域网页面 `Origin` 的写请求（CORS 头本身拦不住跨站 POST）。
  用 curl 调试时要手动加：`-H "Origin: http://127.0.0.1:8080"`。
  同 Wi-Fi 的其他设备只要能打开 App 页面，就仍可使用这两个端口——把网络借给别人前先停服务。
