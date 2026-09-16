# agent-memory-engineering

设计、构建、评估、审计、修复 LLM Agent 记忆与上下文系统的 skill——覆盖完整生命周期（需求 → 架构 → 落地 → 评估 → 调试 → 迁移）。方法论提炼自真实生产系统（FastAPI + LangGraph + PostgreSQL/pgvector）踩过的坑。

> 定位：只覆盖上下文与记忆系统（memory / context engineering），不涉及前端等外围话题。

## 核心信念

- 记忆系统的 bug 几乎都是 **scope/隔离问题**，不是向量相似度问题。
- 上下文的 bug 几乎都是"**错误内容在哪一步第一次进入流水线**"的问题。
- 用现有字段组合表达分层，不为架构图好看建新表。
- memory_type（semantic/episodic/procedural）是与七层正交的分类模型：semantic 对长期事实/偏好类 Memory 通常适用，episodic / procedural 按项目需要启用。Advanced Patterns（background consolidation、progressive disclosure、context planner、graph / bi-temporal…）默认关闭，BUILD 逐项输出 required / recommended / optional / not_needed + reason——敢于说 not_needed 是正确行为。

## 仓库结构

| 文件 | 内容 |
|---|---|
| `SKILL.md` | 入口：按需求选路径（BUILD / AUDIT / DEBUG / 测试）、铁律、三大工作流（BUILD：DISCOVER → MODEL → DESIGN → MAP → IMPLEMENT → EVALUATE；AUDIT：只读体检；DEBUG：INSPECT → REPRODUCE → TRACE → DIAGNOSE → PATCH → VERIFY）、核心模式速查 |
| `references/architecture.md` | Pattern Library：**Core**（七层映射、schema、写入门控、检索/重排、双路由、Forget tombstone、上下文预算）+ **Memory Type Taxonomy**（semantic/episodic/procedural 正交分类）+ **Advanced**（background consolidation、progressive disclosure、context planner、hygiene、entity retrieval、observability）+ **Optional**（graph / bi-temporal / shared memory） |
| `references/testing.md` | 三层测试分类（Universal Hard Invariant / Capability Hard Tests / Quality Metrics）、21 个能力场景、能力 → 场景映射、Root Cause 判定（CASE A–F）、验收指标、Quality Metrics（write / retrieval / context / hygiene / end-task delta / cost） |

## 安装

复制或克隆到 agent 的 skills 目录（以 `~/.agents/skills/` 为例）：

```bash
git clone https://github.com/HuKernel/agent-memory-engineering.git ~/.agents/skills/agent-memory-engineering
```

## 使用

对支持 skill 的 agent（ZCode / Claude Code 等），对话涉及 Agent 记忆、长期记忆、上下文管理、串会话/记忆污染等话题时自动触发。也可按需直接读对应文件：

- **从零设计** → 走 `SKILL.md` 的 BUILD 工作流（DESIGN 阶段完成 Layer / Memory Type / Advanced Pattern / Context Strategy 四项选择，逐项给理由）
- **现有系统有症状**（串会话/记错/污染/答非所问）→ `SKILL.md` 的调试工作流先定位 Root Cause，再查架构对应模式
- **写测试 / 验收 / 评估指标** → `references/testing.md`
