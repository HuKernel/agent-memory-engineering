# Claude Code Adapter

## Skill discovery

Claude Code 从以下位置发现 skills：

- 用户级：`~/.claude/skills/agent-memory-engineering/`
- 项目级：`<project>/.claude/skills/agent-memory-engineering/`

安装器（`./installers/install.sh --target claude`，Windows 用 `install.ps1 -Target Claude`）把 canonical `skills/agent-memory-engineering/` 复制（或 `--link` 软链）过去。`~/.claude/skills/` 下的副本是 installation artifact，不是开发源。

## Plugin 用法（可选）

仓库根的 `.claude-plugin/plugin.json` 让本仓库同时是一个 Claude Code plugin（skills 按 `skills/<name>/SKILL.md` 约定被发现，manifest 的 `skills` 字段指向 `./skills`，不复制内容）：

```bash
# session-only 试载（不写安装记录）
claude --plugin-dir /path/to/agent-memory-engineering

# 或经 marketplace 安装（若已提交官方/私有 marketplace）
claude plugin install agent-memory-engineering
```

plugin 形式下 skill 以 `plugin-name:skill-name` 命名空间出现（`/agent-memory-engineering:agent-memory-engineering`）；普通 skills-directory 安装下就是 `/agent-memory-engineering`。自动触发两种方式都按 SKILL.md 的 `description` 匹配，不受命名空间长度影响。

## 名称取舍

canonical skill name 保持 `agent-memory-engineering`（跨平台统一，Codex 侧 `$agent-memory-engineering` 同名）。虽然 plugin 命名空间形式较长，但 Claude 的 skill 自动触发不依赖 invocation 全名，且改短 skill name 会破坏与 Codex 的统一——不做拆分（如 `agent-memory` + `engineering`）。
