# Agent Memory Engineering

设计、构建、评估、审计、修复 LLM Agent 的**请求理解（Request Understanding & Intent Routing）、记忆与上下文系统**——三者连接成完整的 Agent Runtime Information Architecture（Understand → Route → Retrieve → Plan Context → Act → Update → Evaluate），覆盖完整生命周期（需求 → 架构 → 落地 → 评估 → 调试 → 迁移），提炼自真实生产系统（FastAPI + LangGraph + PostgreSQL/pgvector）的踩坑经验。

Supports:

- Claude Code
- OpenAI Codex
- Agent Skills compatible agents（[skills.sh](https://skills.sh) 生态的 75+ agent）

## Install

```bash
npx skills add HuKernel/agent-memory-engineering
```

No git clone required. No manual copy required. 交互模式下 CLI 会自动检测已安装的 agents 并让你选择。

### Claude Code

```bash
npx skills add HuKernel/agent-memory-engineering \
  --skill agent-memory-engineering \
  --agent claude-code \
  --global
```

非交互版本：

```bash
npx skills add HuKernel/agent-memory-engineering \
  --skill agent-memory-engineering \
  --agent claude-code \
  --global \
  --yes
```

### Codex

```bash
npx skills add HuKernel/agent-memory-engineering \
  --skill agent-memory-engineering \
  --agent codex \
  --global
```

非交互版本：

```bash
npx skills add HuKernel/agent-memory-engineering \
  --skill agent-memory-engineering \
  --agent codex \
  --global \
  --yes
```

### 同时安装 Claude Code + Codex

`--agent` 可重复：

```bash
npx skills add HuKernel/agent-memory-engineering \
  --skill agent-memory-engineering \
  --agent claude-code \
  --agent codex \
  --global \
  --yes
```

先看看仓库里有什么再决定装不装：

```bash
npx skills add HuKernel/agent-memory-engineering --list
```

## Usage

安装后自然提问即可，Claude / Codex 会根据 skill 的 description 自动激活：

- "Help me design the memory and context system for this agent."
- "How should this agent understand user requests and route intents?"
- "Audit the memory architecture in this repository."
- "Why is this agent leaking information between conversations?"
- "Design long-term memory for this coding agent."
- “帮我设计这个 Agent 的长期记忆和上下文系统。”
- “这个 Agent 该怎么理解用户请求、识别意图、做能力路由？”
- “给现有 memory system 做 audit。”

显式调用：Claude Code 中可用 `/agent-memory-engineering`；Codex 中用 `$agent-memory-engineering` 或 `/skills` 查看。两者均支持按对话意图隐式触发。

## What the skill can do

| 你说 | 它走 |
|---|---|
| "从零给 Agent 设计记忆系统" | BUILD 工作流：DISCOVER → MODEL → DESIGN → MAP → IMPLEMENT → EVALUATE（层 / memory type / representation / advanced pattern / routing strategy 逐项选择 + 理由） |
| "Agent 怎么理解请求 / 识别意图 / 做能力路由" | Request Understanding & Routing：多维 request model、Level 0–5 路由分级（含语义向量路由与判定器级联）、路由数据闭环、capability routing、ambiguity fail-closed |
| "帮我看看这个 Memory System 设计得怎么样" | AUDIT 工作流：只读体检 + 差距报告 |
| "Agent 串会话了 / 记错了用户信息" | DEBUG 工作流：INSPECT → REPRODUCE → TRACE → DIAGNOSE → PATCH → VERIFY |
| "把旧的记忆系统迁到新架构" | MIGRATION 工作流：INSPECT → 对齐目标 → 幂等迁移 → VERIFY（旧行 NULL fail closed） |
| "给记忆系统写测试和评估指标" | 三层测试体系（Universal Hard Invariant / Capability Hard Tests / Quality Metrics）+ 能力成熟度三层次（基础回忆 / 多会话检索 / 主动服务）+ 公开基准校准（LongMemEval / LoCoMo 映射） |

核心方法论：Request Understanding & Routing（多维请求模型 / 路由分级含语义向量路由与判定器级联 / 路由数据闭环 / multi-intent / Routing ≠ Authorization / 歧义 fail-closed / paraphrase 鲁棒性）、统一 Runtime Pipeline、Design Artifact Protocol（设计落盘 `AGENT_MEMORY_DESIGN.md` + 跨会话续作 + Definition of Done）、七层记忆模型、semantic/episodic/procedural 分类、Writer 双 candidate source 门控、Forget/tombstone、Normal/Historical 双路由、Procedural Authority Boundary、Structured Core + Raw History、Memory Representation Strategy、Memory Interface Pattern（pipeline / tool / platform）、Context Stability 三段布局、Agent 状态栏（末尾元信息注入）、Sub-agent 上下文隔离、五层压缩分级、31 个能力测试场景、能力成熟度三层次与公开基准校准。纯 instruction + references，无 MCP、无外部服务依赖。

## Repository structure

```text
skills/
└── agent-memory-engineering/     ← 自包含、可单独安装的 Agent Skill
    ├── SKILL.md                  ← 铁律 / 路由表 / 工作流骨架（activation 后全量加载）
    ├── evals/
    │   └── evals.md              ← 触发正负样本 + 工作流 golden trace（维护者自查）
    └── references/
        ├── workflows.md          ← 四工作流执行细则（BUILD / MIGRATION / AUDIT / DEBUG）
        ├── templates.md          ← 产出模板库（Capability Scope / DESIGN 五类 / blueprint…）
        ├── architecture.md       ← memory/context pattern library + 统一 Runtime Pipeline
                                    （Hard Invariant / 七层 / Writer / 检索 / Context Stability…）
        ├── request-understanding.md ← request understanding & routing pattern library
                                    （Request Model / Level 0–5 / taxonomy / fail-closed / 收编表）
        └── testing.md            ← evaluation matrix（31 场景 + 质量指标 + 公开基准校准映射）
```

**渐进式披露**：`SKILL.md` 只放铁律、路由表与工作流骨架（保持精简，进入上下文不挤占用户工作区）；执行细则在 `references/workflows.md`，产出模板在 `references/templates.md`，模式库在 `architecture.md` / `request-understanding.md` / `testing.md`——按需读取，不预加载。

`skills/agent-memory-engineering/` 是唯一内容源（One Skill, One Source of Truth）；安装到各 agent 的副本由 skills CLI 管理。更新本仓库后重跑 `npx skills add HuKernel/agent-memory-engineering` 即可同步。

## Development

```bash
npx skills add HuKernel/agent-memory-engineering --list   # 验证仓库可被发现
```

修改只改 `skills/agent-memory-engineering/` 内的文件；SKILL.md 的 frontmatter 需保持 `name` + `description`（CLI 与各 agent 靠它发现和触发）。

## Versioning

[CHANGELOG.md](CHANGELOG.md)，SemVer。

## License

[MIT](LICENSE) © HuKernel
