# dsh-t3-support

为 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)（dsh）声明 GLM Coding Plan、OpenRouter、OpenAI 等额外模型 provider 路由。本仓库只维护 dsh profile 的 provider 配置，不安装进程包装器。

通过 `providers.yml` 数据文件扩展模型 provider，无需修改安装脚本。

## Agent skill：一句话接入其他厂商模型

dsh 以 ACP 方式接入 T3 Code 时，默认只支持 DeepSeek 官方模型。本仓库自带 agent skill：根目录的 `SKILL.md`。在支持 skills 的 agent 客户端中于本仓库目录内工作时，直接说"帮我加上某个模型"，agent 会自动查注册表、改 `providers.yml`、跑 install 并验证，无需手动执行下文步骤。

想在任意目录使用，可把它链接到自己 agent 的 skills 目录（Codex 为 `~/.codex/skills/`）：

```bash
ln -s "$(pwd)" ~/.codex/skills/dsh-t3-support
```

## 模型路由

### 可用 provider

| ID | 路由 | 凭证 | 模型 / Provider |
|---|---|---|---|
| `glm-cn` | `zai-coding-cn` | `ZAI_CODING_CN_API_KEY` | GLM Coding Plan |
| `zai-intl` | `zai` | `ZAI_API_KEY` | Z.AI 国际版模型 |
| `openai` | `openai` | `OPENAI_API_KEY` | OpenAI / GPT 系列 |
| `anthropic` | `anthropic` | `ANTHROPIC_API_KEY` | Anthropic / Claude 系列 |
| `gemini` | `google` | `GEMINI_API_KEY` | Google Gemini API |
| `openrouter` | `openrouter` | `OPENROUTER_API_KEY` | OpenRouter 聚合模型 |
| `groq` | `groq` | `GROQ_API_KEY` | Groq |
| `together` | `together` | `TOGETHER_API_KEY` | Together AI |
| `qwen` | `qwen-token-plan` | `QWEN_TOKEN_PLAN_API_KEY` | Qwen Token Plan |
| `moonshot` | `moonshotai` | `MOONSHOT_API_KEY` | Moonshot AI / Kimi API |
| `xai` | `xai` | `XAI_API_KEY` | xAI / Grok 模型 |

这些 `route` 与 dsh 内置 pi-ai provider id 对应。dsh 自带的 DeepSeek 官方 API key 与 DeepSeek Account 路由不经过本表维护。

### 安装（macOS / Linux）

```bash
git clone https://github.com/youbuwei/dsh-t3-support.git
cd dsh-t3-support
./install.sh --profile acp --provider glm-cn
```

可组合多个 provider，重复执行幂等：

```bash
./install.sh --profile acp --provider glm-cn --provider zai-intl
```

### 安装（Windows）

Windows 使用 PowerShell。若系统限制脚本执行，可用 `-ExecutionPolicy Bypass` 只对本次命令放行：

```powershell
git clone https://github.com/youbuwei/dsh-t3-support.git
cd dsh-t3-support
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Profile acp -Provider glm-cn,openrouter
```

重复执行幂等。更新 provider 组合时也使用同一条 `-Provider` 列表；未列出的已托管 provider 会继续保留。

Windows 写入的 patch 格式与 macOS / Linux 相同，均为用户目录下 `.dsh/profiles/<profile>/cordis.patch.yml`。

### 凭证

`apiKeyEnv` 只是告诉 dsh 从哪个环境变量解析 key。凭证必须对 dsh 进程可见，或者已保存在 dsh 凭证库中。

macOS / Linux 当前终端会话可使用：

```bash
export OPENROUTER_API_KEY="..."
```

Windows 当前 PowerShell 会话可使用：

```powershell
$env:OPENROUTER_API_KEY = "..."
```

写入用户环境变量可使用：

```powershell
setx OPENROUTER_API_KEY "..."
```

`setx` 只影响之后启动的进程；修改后需要重启 dsh / T3 Code。若从 Desktop App 启动，更稳妥的方式是在 dsh 的凭证管理中保存 key。

### 卸载指定 provider

macOS / Linux：

```bash
./uninstall.sh --profile acp --provider glm-cn
```

Windows：

```powershell
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1 -Profile acp -Provider glm-cn
```

### 添加新的模型 provider

编辑 `providers.yml`，加一条记录即可，无需改脚本：

```yaml
new-model:
  route: some-provider-route
  apiKeyEnv: SOME_API_KEY
  displayName: Some Model Provider
```

前提：dsh 内置的 pi-ai 目录认识该路由（例如 `zai`、`zai-coding-cn`、`openrouter` 等），或者该路由可以在 dsh 的 `llm-pi-ai` 配置中手工声明完整模型。认证 key 需可被 dsh 凭证服务或对应环境变量解析。

## 全部卸载

```bash
./uninstall.sh --profile acp --all
```

Windows：

```powershell
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1 -All
```

## 工作原理

dsh 的 profile 由多层 `cordis.patch.yml` 组合而成。本插件向 profile 的用户 patch 层写入一个带标记的 managed block，把选中的 provider 路由声明给 dsh 内置的 `llm-pi-ai` 服务：

- macOS / Linux：`~/.dsh/profiles/<profile>/cordis.patch.yml`
- Windows：`%USERPROFILE%\.dsh\profiles\<profile>\cordis.patch.yml`

```yaml
- id: llm-pi-ai
  config:
    providers:
      zai-coding-cn:
        apiKeyEnv: ZAI_CODING_CN_API_KEY
        displayName: GLM Coding Plan
```

`route` 必须是 dsh 内置 pi-ai 目录里已有的 provider id。满足这个前提时无需声明 baseURL、模型列表或协议细节；`apiKeyEnv` 会交给 dsh 的凭证服务，并可与进程环境变量配合解析。

注意：dsh 对同一服务 id 的 `config` 采用整体替换（非深合并），所以多个 provider 必须合并在同一个 `providers:` 字典里，由本插件的 managed block 统一维护。

## License

MIT
