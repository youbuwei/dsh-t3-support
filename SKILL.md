---
name: dsh-t3-support
description: 给 T3 Code 的小工具：DeepSeek Harness（dsh）以 ACP 方式接入 T3 Code 时，默认只支持 DeepSeek 官方模型，其他厂商开箱不可用；本工具用于接入其他厂商的模型（如 Kimi、GLM、Gemini、OpenRouter 等）。用户要求"加上 / 配置 / 切换某个模型"或排查 route 未生效时使用；仅使用 DeepSeek 官方模型的日常对话无需此 skill。
metadata:
  short-description: 在 dsh 中配置模型 provider
---

# 给 T3 Code 接入其他厂商的模型

DeepSeek Harness（dsh）以 ACP 方式接入 T3 Code 时，默认只支持 DeepSeek 官方模型，其他厂商的模型开箱不可用。本工具把其他厂商模型（Kimi、GLM、Gemini 等）的 provider 路由配置进 dsh，使其在 T3 Code 中可选。目标：用户一句自然语言（如"帮我加上 Kimi"），就能完成配置并验证生效。按下面顺序执行，不要跳过验证。

## 执行流程

1. `./install.sh --list-providers` 查看 `providers.yml` 已注册的 provider id。
2. 已注册：直接 `./install.sh --profile acp --provider <id>`（可一次传多个）。
3. 未注册：编辑 `providers.yml` 新增一条，不改脚本：

   ```yaml
   new-model:
     route: some-provider-route
     apiKeyEnv: SOME_API_KEY
     displayName: Some Model
   ```

   `route` 必须是 dsh 内置 pi-ai 目录已有的 provider id；不确定时先向用户确认，不要臆造。
4. profile 不存在时，先用 `dsh --profile acp --help` 引导一次再安装。
5. 安装后检查输出：每个 route 应为 `validate : <route> OK`；出现 `MISSING` 说明 route 不被 dsh 识别，回到第 3 步核对拼写或换用已知 route。
6. 凭证检查：确认 `apiKeyEnv` 对应的环境变量已有值（如 `[[ -n "${SOME_API_KEY:-}" ]]`）。没有值时提示用户 `export`（或存入 dsh 凭证库）；Windows 用 `setx` 后需重启 dsh / T3 Code。
7. 完成后告知用户模型已在 dsh 中可用，可在 T3 Code 里选择使用。

## 行为约束

- dsh 对同一服务 id 的 `config` 整体替换、不做深合并。所有 provider 必须合并在同一个 managed block 的 `providers:` 字典里；不要手工编辑 block 内部，也不要在 patch 文件里另建第二个 `llm-pi-ai` 条目。
- `install.sh` 是并集语义：新请求的 provider 加入，已托管但未提及的继续保留。移除用 `./uninstall.sh --profile acp --provider <id>`，不要靠重跑 install。
- patch 文件里已有 managed block 之外的 `llm-pi-ai` patch 时，install 会拒绝；确认无冲突后才可加 `--force`。

## Windows

用 `install.ps1` / `uninstall.ps1`，参数等价：`-Profile`、`-Provider id,id`、`-All`；系统限制脚本执行时加 `-ExecutionPolicy Bypass`。patch 位置为 `%USERPROFILE%\.dsh\profiles\<profile>\cordis.patch.yml`。
