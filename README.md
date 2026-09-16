# agent-memory-engineering

设计、审计、修复 LLM Agent 记忆与上下文系统的 skill。方法论提炼自真实生产系统（FastAPI + LangGraph + PostgreSQL/pgvector）踩过的坑。

> 定位：只覆盖上下文与记忆系统（memory / context engineering），不涉及前端等外围话题。

## 核心信念

- 记忆系统的 bug 几乎都是 **scope/隔离问题**，不是向量相似度问题。
- 上下文的 bug 几乎都是"**错误内容在哪一步第一次进入流水线**"的问题。
- 用现有字段组合表达分层，不为架构图好看建新表。

## 仓库结构

| 文件 | 内容 |
|---|---|
| `SKILL.md` | 入口：按需求选路径、铁律、调试工作流（INSPECT → REPRODUCE → TRACE → DIAGNOSE → PATCH → VERIFY）、核心模式速查 |
| `references/architecture.md` | 七层记忆映射、Memory 表 schema、写入门控、检索/重排、normal/historical 双路由、Forget 抑制（tombstone）、上下文组装与预算 |
| `references/testing.md` | 14 个核心测试场景、Root Cause 判定（CASE A–F）、Trace 最小字段集、验收指标 |

## 安装

复制或克隆到 agent 的 skills 目录（以 `~/.agents/skills/` 为例）：

```bash
git clone https://github.com/HuKernel/agent-memory-engineering.git ~/.agents/skills/agent-memory-engineering
```

## 使用

对支持 skill 的 agent（ZCode / Claude Code 等），对话涉及 Agent 记忆、长期记忆、上下文管理、串会话/记忆污染等话题时自动触发。也可按需直接读对应文件：

- **从零设计** → `references/architecture.md`，按"七层映射 → 写入门控 → 检索 → 摘要 → 预算"顺序
- **现有系统有症状**（串会话/记错/污染/答非所问）→ `SKILL.md` 的调试工作流先定位 Root Cause，再查架构对应模式
- **写测试 / 验收 / 评估指标** → `references/testing.md`
