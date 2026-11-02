# TalkMate 使用说明（傻瓜版）

> 本文面向**便携包**（压缩包内含模型权重）。从 GitHub 拉源码运行时仓库不含模型，请先按 [README.md](README.md) 的「快速开始」准备 Python 与依赖。

## 零、每次电脑重启后（重要）

**网页打不开 / 语音测试失败，通常不是坏了，而是服务还没启动。**  
`8080`（网页）、`8787`（Whisper）、`8788`（TTS）都是随会话起的进程，**关机或重启后会停**。

请做这一件事：

1. 双击 **`02-Start-TalkMate.bat`**
2. 等窗口打印 `App OK / Whisper OK / TTS OK`
3. 浏览器会自动打开 `http://127.0.0.1:8080/`（若没打开，手动访问即可）
4. 要关掉服务（释放端口）：双击 **`03-Stop-TalkMate.bat`**

> **`02-Start-TalkMate.bat` 会帮你打开网页。**  
> 另外：改用手机时，IP 可能变化，以启动窗口打印的 `http://<本机IP>:8080/` 为准（App 也会按打开地址自动配置语音）。  
> 日志在 `%TEMP%\talkmate-logs\`，每次启动会保留上一轮，便于排查。

---

## 一、在新的 Windows 电脑上安装

**压缩包已内置本地模型**（无需再联网下载权重）：

| 模型 | 路径 | 用途 |
|------|------|------|
| faster-whisper **small** | `scripts/models/faster-whisper-small/` | 英语识别 ASR |
| **Kokoro-82M ONNX** | `scripts/models/kokoro-v1.0.onnx` + `voices-v1.0.bin` | 本地 TTS 八档音色 |

0. **请勿用记事本另存修改 .bat 编码**（必须无 BOM / ANSI）。安装与启动脚本已为 ASCII。
### Python 注意（Windows）

若安装后仍报 Python was not found 或 WindowsApps\python.exe，说明系统只有 **微软商店假别名**，没有真正的 Python。

1. 安装：https://www.python.org/downloads/  
2. 安装时勾选 **Add python.exe to PATH**  
3. 可选：设置 → 应用 → 高级应用设置 → **应用执行别名** → 关闭 python.exe / python3.exe 商店别名  

1. 安装 [Python 3.10+](https://python.org)（勾选 **Add python.exe to PATH**）
2. 解压本文件夹（zip 较大，因含模型，属正常）
3. 双击 **`01-First-Install.bat`**（只装 pip 依赖；检测到模型包会跳过下载）
4. 双击 **`02-Start-TalkMate.bat`**（会启动服务并打开浏览器）
5. 使用：`http://127.0.0.1:8080/`（手机：启动窗口里的 `http://<本机IP>:8080/`）

> 仍需联网：pip 装 Python 包、DeepSeek 大模型 API。**ASR/TTS 权重已在包内。**

### 配置大模型（DeepSeek）

App 设置中已预填：

| 项 | 值 |
|----|-----|
| Base URL | `https://api.deepseek.com` |
| 模型 | `deepseek-flash` |

粘贴 **API Key** → 「测大模型」。若模型名无效，可改为 `deepseek-chat`。

## 二、四个模式（聊天记录相互独立）

| 模式 | 用途 |
|------|------|
| **闲聊** | 自由说英语，陪聊 / 严师可切换 |
| **看图** | 描述照片人物互动、物体空间关系 |
| **场景** | 点餐、面试等情景对话（含亲子等专项） |
| **故事** | 童话 / 寓言分幕练习讲述 |

- 每个模式**各自保存**对话记录，切换不会混在一起  
- 底部「传图」按钮上传的图片 **只作为当前模式** 的对话上下文  
- 图片只在**本次打开期间**有效：刷新或关闭页面后需重新上传（文字记录和素材会保留）  
- 「新对话 / 清空」只影响当前模式  

## 三、手机怎么连（自动配置）

1. 手机与电脑连接 **同一个 Wi-Fi**
2. 先在电脑运行 **`02-Start-TalkMate.bat`**
3. 手机浏览器打开窗口里的 `http://192.168.x.x:8080/`
4. App 按打开页面的主机名自动指向 Whisper/TTS
5. 设置里测 Whisper / TTS / 大模型

## 四、电脑宽屏

窗口宽度 ≥ 900px 自动变为 **左侧素材 + 右侧对话**。

## 五、本机语音栈（中档）

| 服务 | 端口 | 说明 |
|------|------|------|
| Web App | 8080 | 浏览器打开这个 |
| faster-whisper `small` | 8787 | 英语识别（包内权重） |
| Kokoro-82M ONNX | 8788 | 本地 TTS 八档音色 |

## 六、常见问题

| 现象 | 处理 |
|------|------|
| **重启后网页打不开** | **运行 `02-Start-TalkMate.bat`**（见本文「零」） |
| 想停服务 / 端口被占用 | 双击 `03-Stop-TalkMate.bat` |
| 测试提示未配置 Key | 设置粘贴 Key 后点「测大模型」 |
| (empty reply) | 检查模型名；看图失败会回退纯文本 |
| 麦克风无权限 | 用 `http://127.0.0.1:8080/`，允许麦克风 |
| 手机连不上 | 同一 Wi-Fi；防火墙放行 8080/8787/8788；以启动窗口 IP 为准 |
