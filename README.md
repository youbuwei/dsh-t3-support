# dsh-t3-support

让 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)（dsh）更好地配合 [T3 Code](https://github.com/pingdotgg/t3code) 等严格 ACP 客户端使用。包含两个可独立装卸的组件：

1. **模型路由**：为 dsh 启用 GLM Coding Plan（智谱）等模型，后续通过 `providers.yml` 数据文件扩展更多模型，无需改脚本。
2. **ACP stdout shim**：清洗 dsh 写到 stdout 的非 JSON-RPC 日志行，修复严格的 ACP 客户端（如 T3 Code）因协议流污染而断开的问题。上游修复后可移除。

## 模型路由

### 可用 provider

| ID | 路由 | 凭证 | 模型 |
|---|---|---|---|
| `glm-cn` | `zai-coding-cn` | `ZAI_CODING_CN_API_KEY` | GLM-5.3、GLM-5.3-Flash、GLM-5.3 Highspeed、GLM-4.6V |
| `zai-intl` | `zai` | `ZAI_API_KEY` | Z.AI 国际版模型 |

### 安装

```bash
git clone https://github.com/youbuwei/dsh-t3-support.git
cd dsh-t3-support
./install.sh --profile acp --provider glm-cn
```

可组合多个 provider，重复执行幂等：

```bash
./install.sh --profile acp --provider glm-cn --provider zai-intl
```

### 卸载指定 provider

```bash
./uninstall.sh --profile acp --provider glm-cn
```

### 添加新的模型 provider

编辑 `providers.yml`，加一条记录即可，无需改脚本：

```yaml
new-model:
  route: some-provider-route
  apiKeyEnv: SOME_API_KEY
  displayName: Some Model Provider
```

前提：dsh 内置的 pi-ai 目录认识该路由（例如 `zai`、`zai-coding-cn`、`openrouter` 等），或者该路由可以在 dsh 的 `llm-pi-ai` 配置中手工声明完整模型。认证 key 需先存入 dsh 凭证库（`~/.dsh/.credentials.yaml`）。

## ACP stdout shim

dsh 0.2.1-rc.2 会把一行模型列表日志写到 stdout，违反 ACP 协议约定，导致 T3 Code 报 `The ACP agent could not create a test session.`。该 shim 包装 `dsh` 启动命令，过滤 stdout、把非 JSON-RPC 行改道 stderr。

### 安装

```bash
./install.sh --with-shim
```

会把 `bin/dsh-acp` 复制到 `~/.local/bin/dsh-acp`。在 T3 Code 中把 provider 的可执行文件从 `dsh` 改成 `dsh-acp`，参数保持 `--profile acp` 不变。

### 卸载

```bash
./uninstall.sh --remove-shim
```

然后把 T3 Code 里的可执行文件改回 `dsh`。

## 全部卸载

```bash
./uninstall.sh --profile acp --all
```

## 工作原理

dsh 的 profile 由多层 `cordis.patch.yml` 组合而成。本插件向 `~/.dsh/profiles/<profile>/cordis.patch.yml` 写入一个带标记的 managed block，把选中的 provider 路由声明给 dsh 内置的 `llm-pi-ai` 服务：

```yaml
- id: llm-pi-ai
  config:
    providers:
      zai-coding-cn:
        apiKeyEnv: ZAI_CODING_CN_API_KEY
        displayName: GLM Coding Plan
```

`zai-coding-cn` 是 dsh 内置 pi-ai 目录里已有的 provider（指向 `open.bigmodel.cn/api/coding/paas/v4`），无需声明 baseURL、模型列表或协议细节；`apiKeyEnv` 会依次从 dsh 凭证服务和进程环境解析。

注意：dsh 对同一服务 id 的 `config` 采用整体替换（非深合并），所以多个 provider 必须合并在同一个 `providers:` 字典里，由本插件的 managed block 统一维护。

## License

MIT
