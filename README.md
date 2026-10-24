# dsh-glm-provider

为 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)（dsh）启用 GLM Coding Plan 模型（GLM-5.3、GLM-5.3-Flash、GLM-5.3 Highspeed、GLM-4.6V）的配置插件。

它通过 dsh 内置的 `llm-pi-ai` 服务注册 `zai-coding-cn` provider 路由，认证复用 dsh 凭证库中的 `ZAI_CODING_CN_API_KEY`（GLM Coding Plan 的 API Key）。安装后，模型会出现在 dsh 会话的模型列表里，包括通过 T3 Code 等 ACP 客户端使用时。

## 前置条件

- 已安装 dsh（`npm i -g @deepseek-ai/dsh`），版本 ≥ 0.2.x
- 目标 profile 已初始化过一次（例如运行过 `dsh --profile acp`）
- GLM Coding Plan 的 API Key 已存入 dsh 凭证库，名称为 `ZAI_CODING_CN_API_KEY`

## 安装

```bash
git clone https://github.com/youbuwei/dsh-glm-provider.git
cd dsh-glm-provider
./install.sh --profile acp
```

安装脚本会向 `~/.dsh/profiles/<profile>/cordis.patch.yml` 追加一个带标记的 managed block，可重复执行（幂等），不会覆盖你的其他配置。

## 卸载

```bash
./uninstall.sh --profile acp
```

## 工作原理

dsh 的 profile 由多层 `cordis.patch.yml` 组合而成。本插件追加的这一层把 `zai-coding-cn` 声明给 `llm-pi-ai` 服务：

```yaml
- id: llm-pi-ai
  config:
    providers:
      zai-coding-cn:
        apiKeyEnv: ZAI_CODING_CN_API_KEY
        displayName: GLM Coding Plan
```

`zai-coding-cn` 是 dsh 内置 pi-ai 目录里已有的 provider（指向 `open.bigmodel.cn/api/coding/paas/v4`），因此无需声明 baseURL、模型列表或协议细节；`apiKeyEnv` 会依次从 dsh 凭证服务和进程环境解析。

注意：dsh 对同一服务 id 的 `config` 采用整体替换（非深合并）。如果你还手工维护了其他 `llm-pi-ai` 配置，请把它们合并进本插件的 block，或使用 `--force` 并自行对结果负责。

## 在 T3 Code 中使用

1. `Settings → Providers → Add provider → Use local command`
2. 可执行文件 `dsh`，参数 `--profile`、`acp`
3. 会话的模型选择器会出现 **GLM Coding Plan** 分组

dsh 0.2.1-rc.2 在 ACP 模式下会把一行模型列表日志写到 stdout，违反 ACP 协议约定，严格的客户端（如 T3 Code）会因此断开。在该问题于上游修复之前，可以用一个 stdout 清洗包装器绕过：把启动命令换成包装脚本，由它过滤 stdout、把非 JSON-RPC 行改道 stderr。

## License

MIT
