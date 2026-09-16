# Agent Memory Engineering

设计、构建、评估、审计、修复 LLM Agent 记忆与上下文系统的跨平台 Agent Skill——同一份 canonical Skill，同时安装到 Claude Code 与 OpenAI Codex。

## What it does

一个触发式可复用工作流 Skill（纯 instruction + references，无 MCP、无外部服务依赖）。当你的 Agent 任务涉及长期记忆、上下文管理、串会话/记忆污染排查时自动介入，提供：

- **BUILD 工作流**：DISCOVER → MODEL → DESIGN → MAP → IMPLEMENT → EVALUATE，从零设计/建设 Memory System
- **AUDIT 工作流**：只读体检现有 Memory System，产出差距报告
- **DEBUG 工作流**：INSPECT → REPRODUCE → TRACE → DIAGNOSE → PATCH → VERIFY，定位串会话/记错/污染类 bug 的 Root Cause
- 七层记忆模型、semantic/episodic/procedural 分类、Writer 门控、Forget/tombstone、双路由检索、Context Stability、Representation Strategy、Structured Core + Raw History、23 个能力测试场景与三层评估体系

## Install

### 前置

```bash
git clone https://github.com/HuKernel/agent-memory-engineering.git
cd agent-memory-engineering
```

### Claude Code（macOS / Linux / Git Bash）

```bash
./installers/install.sh --target claude
```

### Codex（macOS / Linux / Git Bash）

```bash
./installers/install.sh --target codex
```

### Install both

```bash
./installers/install.sh --target all
```

### Windows (PowerShell)

```powershell
.\installers\install.ps1 -Target Claude   # 或 -Target Codex / -Target All
```

默认安装到用户级（Claude: `~/.claude/skills/`；Codex: `~/.agents/skills/`）。项目级加 `--scope project`（PowerShell: `-Scope Project`）。目标已存在且内容不同时安装器会停下提示，`--force` / `-Force` 覆盖（保留时间戳备份）。

### 手动安装（无需脚本）

**Claude Code**：把 `skills/agent-memory-engineering/` 整个目录复制到 `~/.claude/skills/agent-memory-engineering`（项目级：`<project>/.claude/skills/`）。

**Codex**：把 `skills/agent-memory-engineering/` 复制到 `$HOME/.agents/skills/agent-memory-engineering`（项目级：`<project>/.agents/skills/`）。

## Usage

安装后重启宿主（Claude Code / Codex）。Skill 按对话内容自动触发，也可以显式调用：

- **Claude Code**：`/agent-memory-engineering`（作为 plugin 使用时为 `plugin-name:skill-name` 命名空间，见 [docs/claude.md](docs/claude.md)）
- **Codex**：`$agent-memory-engineering` 显式调用，或 `/skills` 查看已装 skill

试一句："帮我设计这个 Agent 的长期记忆和上下文系统。"

## What the skill can do

| 你说 | 它走 |
|---|---|
| "从零给 Agent 设计记忆系统" | BUILD 工作流（层/类型/表示/高级模式四项选择 + 理由） |
| "帮我看看这个 Memory System 设计得怎么样" | AUDIT 工作流（只读体检 + 差距报告） |
| "Agent 串会话了 / 记错了用户信息" | DEBUG 工作流（先复现先 trace 再改） |
| "给记忆系统写测试和评估指标" | 三层测试体系（Universal / Capability / Quality） |

## Repository structure

```text
skills/agent-memory-engineering/   ← canonical Skill（唯一内容源，勿在他处复制）
├── SKILL.md
└── references/
    ├── architecture.md            ← 模式库（Hard Invariant / 七层 / Writer / 检索 / Context Stability…）
    └── testing.md                 ← 测试矩阵（23 场景 + 评估指标）
.claude-plugin/plugin.json         ← Claude Code plugin manifest（引用 skills/，不复制内容）
plugin.json                        ← Agent Plugins portable manifest（同时是 Codex 分发格式）
installers/                        ← install.sh / install.ps1 / uninstall.sh
scripts/validate.py                ← 打包一致性校验
docs/                              ← claude.md / codex.md / compatibility.md
```

`~/.claude/skills/...` 与 `~/.agents/skills/...` 是 **installation artifact**，不是开发源——改内容只改 `skills/agent-memory-engineering/`，重跑安装器同步。

## Development

```bash
python scripts/validate.py                              # frontmatter / 链接 / manifest / 版本同步
./installers/install.sh --target all                    # 冒烟安装
python scripts/validate.py --check-install ~/.claude/skills   # 安装产物与 canonical 一致
./installers/uninstall.sh --target all                  # 清理
```

发布前 smoke test：安装后在 Claude Code 与 Codex 里各发一句 "帮我设计这个 Agent 的长期记忆和上下文系统"，确认 skill 被触发；触发词正/负样本清单见 [docs/compatibility.md](docs/compatibility.md)。

## Versioning

单一版本源：`VERSION` 文件；`plugin.json` 与 `.claude-plugin/plugin.json` 的 version 由 `scripts/validate.py` 校验保持一致。SemVer。

## License

尚未选择——公开分发前请先选定 LICENSE（见 [LICENSE-TODO.md](LICENSE-TODO.md)）。
