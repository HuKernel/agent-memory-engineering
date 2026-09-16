# Codex Adapter

## Skill discovery

Codex 按开放 Agent Skills 标准从以下位置发现 skills：

- 仓库级：从当前目录向上扫描至 repo root 的 `.agents/skills/agent-memory-engineering/`
- 用户级：`$HOME/.agents/skills/agent-memory-engineering/`
- 管理员级：`/etc/codex/skills/`（本仓库不使用）

安装器（`./installers/install.sh --target codex`，Windows 用 `install.ps1 -Target Codex`）把 canonical `skills/agent-memory-engineering/` 复制过去。

## 调用

- 隐式：Codex 按 SKILL.md 的 `name + description` 自动判断适用性（描述已前置触发词）
- 显式：`$agent-memory-engineering`，或 `/skills` 列出已安装 skills

## 分发（plugin 形式）

Codex 官方推荐的可复用分发格式是 **Agent Plugins 开放标准**（universal plugin directory，ChatGPT 与 Codex 共享）——即本仓库根部的 `plugin.json`（`$schema: https://agent-plugins.org/schemas/1.0.0/plugin.schema.json`），skills 按目录约定 `skills/<name>/SKILL.md` 被发现，内容零复制。

Codex 亦支持从其他 repository 安装 skill（`$skill-installer <name>`）——前提是 skill 自包含，本仓库满足：`skills/agent-memory-engineering/` 内只有 `SKILL.md + references/`，无任何 `../../` 外部运行时依赖。

## 未使用 `.codex-plugin/plugin.json` 的原因

当前 Codex 官方文档中没有该专有路径/格式；Codex 的 plugin 分发走根部 Agent Plugins `plugin.json`。凭空创建非标准 manifest 只会制造漂移面，故不建（详见 [compatibility.md](compatibility.md)）。

## 平台专属元数据（YAGNI，未启用）

Codex 支持可选的 `agents/openai.yaml`（display name / icon / invocation policy）。当前默认行为（允许隐式触发）即所需，不加；若未来需要，加在 skill 目录内 `agents/openai.yaml`，Claude 会忽略该文件，不破坏 canonical。
