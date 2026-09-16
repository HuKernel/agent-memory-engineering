---
name: agent-memory-engineering
description: >
  Design, build, implement, evaluate, audit, and debug request-understanding,
  memory & context systems for LLM Agent applications — the full Agent Runtime
  Information Architecture, full lifecycle (requirements → architecture →
  implementation → evaluation → debugging → migration), distilled from a
  production system (FastAPI + LangGraph + PostgreSQL/pgvector). Covers request
  understanding & intent routing (multi-dimensional request model, capability
  routing, routing levels), memory requirements mapping, layer selection,
  memory writer gating, conflict resolution, hybrid retrieval, session /
  conversation isolation, rolling summaries, token budgeting, and
  forget/tombstone suppression. Use whenever the user mentions Agent memory,
  记忆系统, 长期记忆, 上下文管理, context engineering, intent routing, 意图识别,
  意图路由, request understanding, agent runtime architecture, memory writer,
  记忆检索, 记忆污染, 跨会话泄漏/串会话, conversation summary, session
  isolation, or wants to design / build / add / audit / evaluate / refactor /
  fix the request-understanding, memory, or context layer of any AI agent
  project — even if they only describe a symptom like "agent 记错了" or
  "answers mention other conversations".
---

# Agent Runtime Information Architecture：Request Understanding + Memory / Context Engineering（全生命周期实战方法论）

提炼自真实生产项目踩过的坑。覆盖 Agent Runtime 信息架构三大支柱的完整生命周期：**Request Understanding & Routing（请求怎么被理解与调度）+ Memory（跨 session 记什么、怎么读写）+ Context（每个决策点让模型看到什么）**——需求 → 架构 → 落地 → 评估 → 调试 → 迁移。运行时最高原则：**Understand → Route → Retrieve → Plan Context → Act → Update → Evaluate**（完整管线图见 `references/architecture.md` 开篇；路由模式库 `references/request-understanding.md`）。核心信念：**记忆系统的 bug 几乎都是 scope/隔离问题，不是向量相似度问题**；上下文的 bug 几乎都是"错误内容在哪一步第一次进入流水线"的问题；路由的 bug 几乎都是"把理解降级成单标签分类"或"把路由建议当权限"的问题。

## 术语约定

全文 **thread == conversation == 会话**（同一概念；字段名以目标项目为准，下文统称 thread）。**scope** 是记忆的可见范围：`global`（用户级）/ `thread`（会话级）/ `project`（项目级）——global 即 user 级，不承载 system-wide / agent-wide 语义。**authority** 是 procedural instruction 的行为优先级，与 scope 正交（scope = 谁能看到，authority = 行为优先级多高）——scope=project 不自动等于 Project Hard Rule（architecture.md §9.6）。**memory_type** 是正交的信息性质分类，值域仅 `semantic` / `episodic` / `procedural`；decision 等领域维度走 `domain` 字段（如 `domain='decision'`），不占 memory_type 值域。**digest** 指会话标题列表 + 资产清单的轻量快照（user 级）。**Request Understanding & Routing** 指请求进入后的理解与调度层：产出多维 **request model**（intent × scope × temporal × information needs × action × capability_plan，维度正交），**scope_intent / temporal_intent** 收编现有会话范围路由与 Normal/Historical 双路由的触发判定（实现不变）；请求侧 `scope_intent.level=user` 即存储侧 scope `global`。**Router 不是授权方**：routing 结果不构成权限（Routing suggests. Authorization decides. Visibility enforces.）。

## 按需求选路径

| 用户要什么 | 做法 |
|---|---|
| 不知道 Agent 怎么理解请求 / 识别意图 / 做能力路由 | 读 `references/request-understanding.md`；BUILD（Capability Scope: request_understanding=required） |
| 不知道怎么设计长期记忆 / 跨会话恢复 | Memory BUILD：MODEL 的 Information/Memory Modeling + DESIGN 选层选型 |
| 不知道怎么做 Context Management / token budget / summary / compression / stable prefix | Context BUILD：DESIGN 的 Context Strategy / Context Planner（architecture.md §5–§6、§9.5） |
| Agent Runtime 整体设计（Intent + Memory + Context） | Integrated BUILD：三支柱联合设计（先做 Capability Scope Decision） |
| 已有 Agent Runtime / Memory / Context 架构，想评估设计质量 | 走「AUDIT 工作流」：只读检查 + 差距报告，默认不改代码 |
| 系统有症状（串会话/记错/污染，或 意图识别错误/路由错误/工具选错/能力误激活/错误跨会话历史检索） | 走「调试工作流」定位 Root Cause（CASE R / A–F），再查对应 reference：routing → `request-understanding.md`；memory/context → `architecture.md`；测试 → `testing.md` |
| 要写测试 / 验收 / 评估指标 | 读 `references/testing.md`，按项目能力选场景 |

## 铁律（冲突时按此序裁决）

1. 正确性 > 防记忆污染 > 上下文相关性 > 可维护性 > 性能 > Token 成本。
2. Memory ≠ 聊天记录；Context ≠ 全部历史。写库前必须过门控，进 prompt 前必须过预算。
3. **先复现、先 trace，再改代码**。Root Cause 未定位前禁止重构。
4. 会话/scope 隔离错误，禁止用"调 embedding 相似度阈值 / 换向量库"来修——那是把路由错误当检索问题治。
5. 没有 UI/API 消费方的 Schema 不要建（projects/tenant/memory_versions 表大多是 YAGNI；版本史用 `superseded_by` 链表达）。
6. 模型推断不得覆盖用户明确陈述（explicit > inferred_strong > inferred_weak）；写入门控 LLM 判定失败时默认不写，宁漏勿错。
7. 临时/可变状态（进度百分比、资产清单、本周在哪）不写入长期记忆——实时查询才是 Source of Truth。
8. 被 Forget 的事实不得回流最终 prompt：tombstone 在注入期屏蔽旧摘要/digest/缓存里的原话（`references/architecture.md` §5）；仅靠"以记忆段为准"的仲裁声明不够。
9. **Routing 只建议、不授权**：路由结果不构成 tool authorization、不扩大 Memory visibility（Routing suggests. Authorization decides. Visibility enforces.）；intent 歧义 fail closed——默认解析到当前/更小 scope，绝不扩大可见范围；"记住 X" 只产生 memory_write_candidate，必须仍过 Writer 门控（`references/request-understanding.md`）。

**参数哲学**：本文与 references 里的一切数字（阈值/权重/窗口/预算）都是 **Recommended Default**——经验起点，应通过真实数据集与 eval 校准，不是架构真理。Hard Invariant 是行为约束（见 `references/architecture.md` §0；测试分三层——Universal Hard Invariant / Capability Hard Tests / Quality Metrics，见 `references/testing.md`），与数字无关，不许放松。

## BUILD 工作流：DISCOVER → MODEL → DESIGN → MAP → IMPLEMENT → EVALUATE

为从零设计、重建或接入 **Agent Runtime Information Architecture**（Request Understanding / Memory / Context）的项目服务，按用户实际需求选择需要的能力，**不要求三个模块同时重建**：Intent-only task 不强制重建 Memory；Memory-only task 只做必要最小 Request Understanding 设计；Context-only task 不强制新增长期 Memory；Integrated Agent Runtime task 三者联合设计。`references/architecture.md` 是 Memory/Context 的**模式库不是模板**，`references/request-understanding.md` 是请求理解与路由的模式库——每一步都在做“选择 + 说理由”，不是照抄全套；DESIGN 阶段必须完成 **Layer / Memory Type / Representation / Advanced Pattern / Context Strategy（含 Context Stability）/ Routing Strategy** 选择，流程不另加阶段。全程约束：铁律 1–9、YAGNI、复用现有栈、minimal change、可测试；最高取舍序 **Correctness → Relevance → Adaptivity → Maintainability → Efficiency**，复杂度只在有理由时引入。

**Capability Scope Decision**（BUILD 第一个动作——任务范围判断，不是 runtime schema、不是 DB 结构、不是新 Pattern；防止 Intent-only 被强推整套 Memory、Context-only 被强推长期 Memory）：

```yaml
task_capabilities:            # 每项必带 reason
  request_understanding:
    status: required | relevant | not_needed
  memory:
    status: required | relevant | not_needed
  context:
    status: required | relevant | not_needed
```

### 1. DISCOVER —— 理解产品，而不是立刻套架构

先从代码库 / PRD / schema / 现有实现**推断**答案；只有影响架构且确实缺失的信息才问用户，不发问卷。

```yaml
product_context:
  agent_type:            # Agent 是干什么的
  user_model:            # 谁在用；是否多用户
  conversation_model:    # 是否跨会话回归；会话如何创建识别
  has_projects:          # 产品是否存在 project 概念
  has_tasks:             # 是否有跨轮任务运行态
  has_rag:               # 是否有文档库/知识检索
  has_tools:             # 是否有工具/API 调用
  external_mutable_data: # 实时可变数据（资产/进度/价格…）
  persistence:           # 现有 DB 与 ORM
  vector_store:          # 现有向量库（没有则标注）
  cache:                 # 现有缓存设施
  history_requirements:
    needs_cross_session_detail_retrieval:  # 是否需要跨会话细节回溯 → raw history 选型
    expected_history_horizon:              # 历史视野（天/月）→ retention 与索引策略
  retention_privacy:
    raw_history_retention:                   # raw history 保留策略
    supports_user_forget:                    # 是否支持 forget_for_inference
    requires_hard_delete_or_privacy_erasure: # 是否要求 hard-delete / privacy erasure
  model_context:
    context_window:                          # 模型 context window
    prefix_cache_supported:                  # provider 是否支持 prefix cache
  routing_requirements:
    intent_sources:                          # 可推断 intent space 的来源（PRD/API/tools/现有 routes/user journeys）
    existing_router:                         # 已有路由实现（none/rules/llm）
    specialist_agents:                       # 是否存在真正需要独立 prompt/工具/权限的 specialist
```

新增的 history_requirements / retention_privacy / model_context 仍优先从代码 / config / provider SDK / PRD **自动推断**，只有影响架构且确实无法推断才问用户——它们决定 DESIGN 阶段的 Raw History Retrieval、Context Stability / Cache Strategy、Retention / Erasure 选型。routing_requirements 决定 Routing Strategy 选型（request-understanding.md §2），并从 intent_sources 推断 **Intent Space**（request-understanding.md §3：taxonomy 来自产品，禁止内置通用分类，必有 unknown 兜底）。

同时判定三件事：哪些信息需要长期记忆、哪些只是短期运行状态、哪些已有独立 Source of Truth（有 SoT 的只实时查询，铁律 7）。

### 2. MODEL —— Runtime Requirement Modeling（capability-selective）

先建模，不先设计数据库。按 Capability Scope Decision 拆两个子模型，核心原则 **No consumer → No field**，不强制全字段输出。

**A. Request Modeling**（request_understanding = required / relevant 时；字段按 `request-understanding.md` §1 裁剪原则决定）：

```yaml
request_mapping:
  intent:
  scope_intent:
  temporal_intent:
  information_needs:
  action_need:
  capability_plan:
```

**B. Information / Memory Modeling**（memory = required / relevant 时，即原 Memory Requirement Mapping）——每类信息建立映射：

```text
信息 → 生命周期(long/task/session/request) → scope(global/thread/project)
     → memory_type(semantic/episodic/procedural) → representation(表示策略，architecture.md §2)
     → Source of Truth → 是否长期记忆 → Storage → Retrieval Route
```

memory_type 与 scope/生命周期**正交**（architecture.md §9.1 taxonomy）：semantic = 稳定事实/偏好，episodic = 过去任务的成败经验，procedural = Agent 行动规则——组合如 User+Semantic、Project+Episodic 都是合法的。decision 不是 memory_type 值：决策类信息 = `semantic + domain='decision'`，历史决策事件 = `episodic + domain='decision'`。global procedural = 针对当前 user、跨 thread/project 的行为偏好或工作习惯（"给我代码前先解释"），不是 system-wide 规则——后者属 trusted system policy / agent configuration，不入 user memory 表。

**Representation Strategy**（architecture.md §2，设计决策维度，不是 DB 字段）：`atomic_note`（单一事实/简单偏好）/ `enhanced_note`(需少量上下文才独立理解) / `structured_card`（多字段稳定实体；局部更新 = 逻辑 field patch + 持久化全量快照走 SUPERSEDE）/ `rich_contextual_card`（复杂事件/关系/决策，携带 entity/relationship/backstory/provenance）/ `raw_history_reference`（指向 raw conversation archive 的引用，不是新的长期事实 memory）。**Representation 不绑定 memory_type**——由信息复杂度、更新频率、关系复杂度、检索方式、token cost 共同决定（Semantic+atomic_note 与 Episodic+rich_contextual_card 都合法）。优先按 Information → Memory Type → Representation 逐条映射：

```yaml
information_mapping:
  - information: user preference
    scope: global
    memory_type: semantic
    representation: atomic_note
  - information: project architecture decision
    scope: project
    memory_type: semantic
    domain: decision
    representation: rich_contextual_card
  - information: work profile（可局部更新的稳定实体）
    scope: global
    memory_type: semantic
    representation: structured_card
```

例：「用户喜欢深色主题」→ 长期 / global / semantic / atomic_note / 用户明确陈述 → **是**长期记忆 → memory 表 → 正常召回。
例：「项目决定使用 PostgreSQL」→ 长期 / project / semantic + domain=decision / rich_contextual_card → **是**长期记忆（决策状态/理由/备选放 structured_data）→ memory 表 → 正常召回。
例：「上次部署失败因 migration 未锁表」→ 长期 / project / episodic / enhanced_note → **是**长期记忆（历史经验，不因新事实过期；普通召回显著性可衰减——只要未 forget、未 hard-delete、仍在 retention policy 内，显式历史查询可从 active/cold/archive tier 恢复）。
例：「当前任务完成 70%」→ task / task state 是 SoT → **不是**长期记忆 → 结构化运行态 → 实时读取。

**Capability-selective 规则**（两个子模型按任务范围启用）：

```text
Request/Intent-only project:  Request Modeling = required；Memory Modeling = only if relevant
Memory-heavy project:         Memory Modeling = required；Request Modeling = minimal（只建 routing 必要输入）
Context-only optimization:    只建 Context Planner 真正需要的 request dimensions
Full Agent Runtime:           Request Modeling + Information/Memory Modeling
```

最常见反模式 = 把所有东西塞进 Memory Table。分类结果就是选层与写策略的输入。

### 3. DESIGN —— 按需选层，逐层说理由

七层（architecture.md §1）逐层判定 status + reason：

```yaml
selected_layers:
  working:
    status: required
    reason: "所有请求都需要 request-scoped state"
  session:
    status: required
    reason: "窗口原文与会话摘要构成会话上下文主体"
  task:
    status: required
    reason: "存在跨轮任务运行态"
  project:
    status: not_needed
    reason: "产品不存在 project 概念，YAGNI"
  user:
    status: required
    reason: "跨会话偏好/事实需要长期记忆"
  knowledge:
    status: optional
    reason: "有课程文档 RAG 时启用"
  external:
    status: optional
    reason: "有实时可变数据时经工具当次注入"
```

必须能回答：**为什么这个项目需要这一层、为什么不需要另一层**。同样输出 memory_type 与 advanced_patterns（architecture.md §9–§10）：memory_type 按 §9.1 taxonomy 给 status——semantic 对长期事实/偏好类 Memory 通常 required，episodic/procedural 按项目需要；advanced_patterns 逐项判定，默认 not_needed。唯一例外是 §9.6：procedural memory 启用时其 authority boundary **自动强制**（mandatory guardrail），不参与选配、不能关闭：

```yaml
memory_types:
  semantic:
    status: required
    reason: "用户偏好与约束"
  episodic:
    status: recommended
    reason: "跨会话复用排障经验"
  procedural:
    status: not_needed
    reason: "个人聊天 Agent，无稳定行动规则"

advanced_patterns:
  background_consolidation:
    status: recommended
    reason: "多轮行为模式需要沉淀，且不进 critical path"   # §9.2
  progressive_disclosure:
    status: not_needed
    reason: "上下文体量小，Tier 3 目录无增益"              # §9.4
  context_planner:
    status: optional
    reason: "查询类型分档差异大时启用 token 动态预算"      # §9.5
  entity_retrieval:
    status: optional
    reason: "查询常含实体名，三路召回有增益"               # §9.8
  graph_memory:
    status: not_needed
    reason: "无多跳关系查询，图库是纯负担"                 # §10.1
  bitemporal_memory:
    status: not_needed
    reason: "非 CRM/finance/时间线类项目"                  # §10.2
  shared_memory:
    status: not_needed
    reason: "单 Agent，无协作共享态"                       # §10.3
```

layer status 只能取 required / optional / not_needed；memory_type、representation 与 advanced pattern status 只能取 required / recommended / optional / not_needed——**每项必须带 reason，不允许只有 status 的输出**；**敢于输出 not_needed** 是本 skill 的正确行为，不是遗漏。

**Representation 与 Context Stability 也是 DESIGN 输出**（前者也可在 MODEL 的 information_mapping 逐条给出）：

```yaml
representation_strategy:        # architecture.md §2；按信息类选型，不绑定 memory_type
  atomic_note:
    status: required
    reason: "用户偏好/简单约束为主"
  structured_card:
    status: optional
    reason: "存在稳定实体档案（工作画像等）需局部更新"
  rich_contextual_card:
    status: not_needed
    reason: "当前长期记忆主要是简单 preference，atomic notes 已足够"
  raw_history_reference:
    status: required
    reason: "用户常询数月前决策细节，Core 无法保存全部证据"
```

**Structured Core vs Raw History**（architecture.md §1，**Core Design Question**）：每个 BUILD 必答三问——是否保留 raw source？是否需要 searchable raw history？是否需要 Overview → Detail？——答案取 required / optional / not_needed（简单 preference chatbot：Core required / Searchable Raw History not_needed，**不为长期记忆自动建 raw-history 索引**；Coding / Research Agent：Raw History Retrieval recommended 或 required）。Core 是 navigation/overview，Raw 是 detail/evidence；普通问题走 active memory，detail lookup / 显式历史意图才回 raw（双路由不变）；raw 保留受 retention / privacy / deletion policy 管辖——append-only 指不为摘要/Memory 更新重写，不表示不可删除。

**Context Stability**（architecture.md §6/§9.5）：BUILD 输出 stable_prefix / semi_stable / dynamic_tail 分段与 cache_strategy（Context Architecture Decision，不强制新增 runtime schema）；provider 无可利用 prefix cache 时保留 stable-prefix 布局、cache benefit 标 not_applicable。

**Routing Strategy**（request-understanding.md §1–§7）：BUILD 输出路由分级、request model 裁剪与 intent taxonomy——**simplest sufficient router**，从 Level 0 往上找第一个够用的，不从 Level 3 起步；request model 按项目裁剪，字段必须有消费方，禁止全字段堆砌：

```yaml
routing_strategy:
  level: 3                     # 0–5（request-understanding.md §2）；每级必须带 reason
  reason: "自然语言 scope + 组合意图，确定性规则覆盖不足"
  request_model:               # §1 Recommended Schema 的裁剪结果
    fields: [primary_intent, scope_intent, temporal_intent, capability_plan, ambiguity]
    dropped: [risk, secondary_intents]   # 无工具无副作用 → 删，写理由
  intent_taxonomy:             # §3；mode closed/open/hybrid + unknown/other 兜底
                               # intents 带 definition/examples/boundary/counterexamples/route_target
  handoff_policy: not_needed   # Level 5 才填；handoff vs agent-as-tool 判定（§9）
```

铁律 9 在此落地：capability_plan 只建议不授权，ambiguity fail closed，routing 输出不进 Stable Prefix（request-understanding.md §0/§5/§8.4）。

随后按 architecture.md 模式设计：Writer 门控 / Visibility / 冲突消解 / Forget / 检索与双路由（含 Raw History Retrieval）/ 摘要 / Context Builder（含三段布局）/ 预算（启用 Planner 时按 §9.5 token 化 + 双目标）/ RAG 与 Tool 隔离。偏离模式库的每一处都要写理由；没有理由就照模式库。关键取舍记入 architecture_decisions，让用户知道“为什么没用某个高级方案”：

```yaml
architecture_decisions:
  - pattern: graph_memory
    decision: not_needed
    reason: "只需要用户偏好与简单项目事实，无多跳关系查询"
    alternatives_considered: ["pgvector + entities JSONB"]
    why_not: "无关系遍历需求，图库是纯负担"
  - pattern: rich_contextual_card
    decision: not_needed
    reason: "当前长期记忆主要是简单 preference，atomic notes 已足够"
  - pattern: raw_history_retrieval
    decision: required
    reason: "用户经常询问数月前具体决策细节，Core Memory 无法保存全部证据"
```

### 4. MAP —— 映射到现有技术栈

先识别现有栈（语言 / Agent 框架 / DB / 向量库 / 缓存），再把 Pattern → Existing Component，**优先复用**，不为符合本 skill 新建重复基础设施：

```text
Task Memory          → LangGraph State / 请求 State
User Memory          → 现有 PostgreSQL 表 + pgvector
Knowledge Retrieval  → 现有 Qdrant collection / ES 索引
Short-lived cache    → Redis
```

FastAPI + LangGraph + PostgreSQL/pgvector 只是参考实现，不是要求。

### 5. IMPLEMENT —— 落地

**Host capability 语义**：本节按宿主实际能力执行——host 提供文件读写 / shell / 测试运行能力时直接执行；某项能力不可用时对该项降级为 implementation-ready 计划，不虚构执行结果。能用则用，不能用则明说；这不削弱自主执行原则。

- **有代码**：主动读项目找 request entry、LLM 调用链、message storage、persistence、vector retrieval、context builder、summary、tests → 输出 implementation plan（Schema/Model、Writer、Retrieval、Context Builder、Summary、Routing、Tests、Migration）→ 直接落地实现。仍守 minimal change / reuse / YAGNI。

**自主执行边界**：用户已明确请求"设计并实现 / 帮我把 Memory 做好 / 接入 Memory / 直接改"时，DISCOVER → EVALUATE 连续完成，**不在 DESIGN 后默认停下二次确认**。只有这些情况必须停下来问：destructive migration、数据删除、不可逆 schema change、涉及生产数据的大规模迁移、两种方案都会显著改变产品行为且现有上下文无法裁决、缺失会改变架构的关键业务信息。新增 service/repository/memory writer、调整 context builder、加测试、加普通 schema field——属原始请求范围内的正常实现，无需再确认。
- **无代码（只有产品需求）**：输出 Implementation-ready Blueprint，工程师可直接开工：

```yaml
memory_system_blueprint:
  product_model:               # DISCOVER 结论
  selected_layers:             # DESIGN 结论
  memory_types:                # DESIGN 结论（semantic/episodic/procedural）
  advanced_patterns:           # DESIGN 结论 + architecture_decisions
  information_mapping:         # MODEL 结论
  write_policy:                # what_to_store / what_not_to_store / explicit_vs_inferred
                               # / dedup / conflict_resolution / forget / background_consolidation
  retrieval_policy:            # visibility / normal_route / historical_route
                               # / hybrid_retrieval / reranking / entity_retrieval
  context_policy:              # blocks / priority / budgets / drop_policy
                               # / progressive_disclosure / context_planner（§9.5）
  context_stability:           # stable_prefix / semi_stable / dynamic_tail
                               # / cache_strategy（§6；含 not_applicable 判定）
  request_routing_policy:      # request-understanding.md：routing level + reason
                               # / request_model 裁剪 / intent_taxonomy + unknown 兜底
                               # / capability_plan 键集与物理跳过映射
                               # / ambiguity fail-closed + material 澄清
                               # / routing_trace（不永久记录 raw user text）
  representation_strategy:     # information → representation 映射（§2）
  long_term_information:       # structured_core / raw_history_archive / retrieval
                               # 的 required/optional/not_needed 判定（§1 / §4）
  compression_strategy:        # 压缩优先序 + SummarySegment 约束（§5）
                               # 不需要的项明确写 not_needed + reason，不留空
  summary_policy:
  storage_design:              # 表 schema / 向量库 / 缓存 key 设计
  implementation_components:   # Pattern → 现有组件清单
  evaluation:                  # required_tests / metrics
```

### 6. EVALUATE —— 按能力选测试，不机械全跑

按 `references/testing.md` 三层分类选择：**A. Universal Hard Invariant**（§6 泄漏/回流 = 0 类，启用对应基础能力即必须满足）+ **B. Capability Hard Tests**（§1 场景 × §7「能力 → 场景映射」，能力启用才必测——如：有长期 User Memory → 1/5/6/7/14；支持 Forget → 11/15；启用 Request Understanding / Router → 24–31（capability-selective，见 §7）；无 project → 跳过 13 并写 reason）+ **C. Quality Metrics**（§8–§11：write / retrieval / routing / context / maintenance / end-task delta / cost）。未启用的能力跳过对应场景并在 skipped_tests 写 reason，不机械全跑；**Metric 阈值按项目校准，不是全项目统一硬门槛**。

```yaml
evaluation_plan:
  required_tests: []
  optional_tests: []
  skipped_tests:
    - test: 场景 9
      reason: "无 RAG，仅保留工具结果断言"
  quality_metrics: []          # 选用的 §8–§11 指标 + 项目校准阈值
```

### 7. 运行期 —— OBSERVE / MAINTAIN（IMPLEMENT 之后）

上线不是终点：接 memory_trace 观测（§9.9：routing / write / retrieval / context / usage 五段；routing 段见 request-understanding.md §10），按 §9.3 触发条件跑 Memory Hygiene（merge / supersede / promote，保留 provenance、不动 explicit），用 testing.md §8 Routing Quality 与 §9–§10 的 Hygiene 曲线、End-task Delta 持续验证 Memory 真的在帮 Agent。

## AUDIT 工作流（只读体检，默认不改代码）

用户要求审查现有 Agent 的 request understanding、intent routing、memory 或 context architecture（如"帮我看看这个 Memory System / 路由层设计得怎么样"）时走这条路。只读检查、产出差距报告；默认不改代码。用户要求修复时**转「调试工作流」**，默认从 REPRODUCE / TRACE 开始建立修复证据；只有 AUDIT 已同时具备 稳定复现、failing test、first contamination point、root cause、high-confidence 证据时，才允许带证据直接进 PATCH——不为省重复步骤跳过 Root Cause 证明。

```text
INSPECT → CHECK INVARIANTS → CHECK MAPPING → CHECK ROUTING PATH → CHECK WRITE PATH
→ CHECK READ PATH → CHECK CONTEXT PATH → SELECT TEST MATRIX → REPORT GAPS
```

1. **INSPECT**：只读侦察，同调试工作流 INSPECT 的 8 个检查点，但对象是整个系统而非单个 bug。
2. **CHECK INVARIANTS**：对照 architecture.md §0 的 10 条 Hard Invariant 逐条判定 满足 / 违反 / 不适用（含 §0.9 Routing ≠ Authorization、§0.10 歧义 fail closed——启用路由的系统必查）。
3. **CHECK MAPPING**：可变状态是否进了长期记忆？实时数据有没有独立 Source of Truth？RAG/工具结果是否被持久化成 memory？
4. **CHECK ROUTING PATH**（request-understanding.md）：request model 是否按项目裁剪（无消费方字段 = 反模式）？intent taxonomy 是否来自产品能力而非内置通用分类？unknown / other 兜底是否存在？scope / temporal 判定是否正确？capability_plan 是否与 request model 一致？false capability 是否物理跳过？routing 是否错误扩大 visibility？router 是否错误承担 authorization（§0.9）？ambiguity 是否 fail closed（§0.10）？routing output 是否误入 Stable Prefix？handoff / specialist 是否过度设计（intent label ≠ Agent）？职责边界：**Routing Path 查"为什么选择这些能力"，Read Path 查"这些能力如何安全读取数据"**——不重复 architecture.md 的 Memory Visibility 检查。
5. **CHECK WRITE PATH**：写入门控、查重、冲突消解、证据优先级（explicit > inferred_*）。
6. **CHECK READ PATH**：Visibility 硬过滤（user → scope → status → valid_to）、Normal/Historical 双路由、缓存 key 是否含会话维度。
7. **CHECK CONTEXT PATH**：段清单、预算与丢弃顺序、能力门控、tombstone 注入期屏蔽。
8. **SELECT TEST MATRIX**：按启用能力从 testing.md 选场景（同 BUILD 的 EVALUATE）。
9. **REPORT GAPS**：结构化输出 `{gaps: [{severity, violated_invariant, location, fix_hint}], test_matrix, priority}`，修复优先级按铁律下的 PATCH 优先序（Authorization / Scope Isolation > Request Routing > Retrieval Filter > …）排。

## 调试工作流：INSPECT → REPRODUCE → TRACE → DIAGNOSE → PATCH → VERIFY

对“系统答出了不属于当前上下文的内容”“意图识别 / 路由 / 能力激活错误”类 bug 严格按序执行。每阶段有明确禁令；跳阶段（没复现就改码、没 DIAGNOSE 就重构）= 返工。

### 1. INSPECT —— 只读侦察

只允许：读代码、追调用链、理数据流、找 scope 过滤、找检索来源、找 context 组装方式。

- 从请求入口逐函数追到 LLM 调用点，不靠文件名/函数名猜功能。
- 查 8 个点：会话如何创建识别 / 消息绑定哪些 id / 历史查询的 WHERE 条件 / 记忆检索默认范围 / summary 从哪些会话生成 / 缓存 key 是否含会话维度 / "这个会话"类问题被路由到什么数据源 / 最终 prompt 里各段从哪来。

**禁止**：修改任何代码、配置、schema、阈值。

### 2. REPRODUCE —— 没有 failing test 不动手

- 真实环境复现：构造最小对话（A 会话放干扰内容，B 会话只放一句引导语），在 B 里问"这个会话里我问过什么"。混入内容若与某个中间产物（digest/召回结果/摘要）逐字对应 = 注入实锤，非幻觉。
- 自动化复现：写成 pytest 用例，**修复前必须 FAIL**（bug 的可重复证据），修复后必须 PASS。
- **无法稳定复现 → 停在这里**。只加 logging/trace 找触发条件，不改任何代码（见 TRACE 的 CASE F）。

### 3. TRACE —— 找错误第一次出现的位置

```
R. Request Understanding / Routing → request model 判定已错：scope/temporal/capability_plan 误判
                                     （查 routing_trace：rule_hits / llm_router.decision /
                                      fallback_reason / ambiguity / authorization_checks）
A. 数据库/存储查询    → 查询缺 scope 过滤（只有 user_id 没有 thread_id）
B. 检索阶段          → digest/向量检索按 user 级取数，混入了其他会话内容
C. 摘要/压缩阶段     → summary 管线聚合了别的会话
D. 上下文组装阶段    → 检索结果正确，但 Builder/Planner 把错误源拼进了最终 prompt
E. LLM/执行阶段      → 最终 context 完全正确，模型自己编的
F. 无法稳定复现      → 回 REPRODUCE 加 observability，禁止改架构
```

典型规律：DB 层通常是对的（ORM 过滤天然正确），**泄漏首现于 B 或 D——某个“便利 digest”按 user_id 取了跨会话数据**。LLM 很少是无辜的：它只是忠实复述被注入的内容。启用路由的系统先判 R——**Routing 错误是独立 first failure point**：用户明确问“这个会话里……”而 Router 产出 user + historical，first failure point 是 R 不是 B，即使 Retrieval 忠实执行了错误 route（downstream symptom 不改判分类）。Routing 根因的修复优先补确定性规则 / fail-closed 默认值（request-understanding.md §4/§5），不是调检索权重。

### 4. DIAGNOSE —— 结构化结论（先报告，后动手）

```yaml
symptom:
expected:
actual:
first_contamination_point:   # R / A–F 分类 + 文件:函数
root_cause:
evidence:                    # failing test 名 / trace 片段；无证据 = 无结论
confidence:                  # high | medium | low；low 则回 TRACE
affected_scope:              # 受影响的 scope 与查询路径
routing_evidence:            # 仅 first_contamination_point=R 时输出（capability-selective，不要求所有 bug 都有）
  expected_request_model:
  actual_request_model:
  rule_hits:
  fallback_reason:
```

### 5. PATCH —— 最小修改

修复优先级：**Authorization / Scope Isolation > Request Routing > Retrieval Filter > Summary Isolation > Context Planner / Builder > Prompt > Reranking**——Routing 根因有明确位置，但不凌驾 Authorization / Scope Hard Guard。

- minimal patch 优先：改一个 WHERE 条件优于改检索策略，改检索策略优于调重排权重，任何都优于重设计管线。禁止借修 bug 顺手重构 Memory System。
- 动手前先向用户说明：bug 在哪个文件哪个函数、为什么发生、改什么、影响面。

### 6. VERIFY —— 核心回归 + 能力回归全绿才算完

固定核心回归（每次必跑）：

1. 原 bug 的 failing test 转 PASS；
2. 跨会话隔离：testing.md 场景 2（B 会话零泄漏）；
3. 合法跨会话不误伤：显式问"以前聊过什么"仍能召回；
4. 用户级 global memory 不误伤："我通常喜欢什么"仍工作；
5. superseded 记忆不回流 normal route：场景 1；
6. 重复记忆不重复召回：场景 7；
7. context token 有界：场景 4。

再加**能力回归**：列出本次修改的 affected_capabilities，按 testing.md §7 Capability Hard Tests「能力 → 场景映射」选测试——改 Forget 跑 11/15；改 Project Visibility 跑 12/13；改 valid_to 跑 14；改 Historical Route 跑 10；改 Writer 输入边界跑 9；改 Procedural 写入/注入跑 19；改 Raw History Retrieval 跑 20/21；改 Derived Writer / lineage 过滤跑 22；改 Context Stability / stable prefix 布局跑 23；改 Request Understanding / Router baseline（含 capability 门控、ambiguity、taxonomy）跑 24/25/26/27/28；改 multi-intent 跑 29；改 routing 注入防护跑 30；改语义 / LLM router 跑 31 + §8 Routing Quality。原则：**修改影响到的 capability，其对应测试必须全部通过**。

## 核心模式速查（详细版在 references/architecture.md 与 references/request-understanding.md）

**请求理解与路由（Request Understanding & Routing）**：不是 `query → label` 的 intent classifier，输出多维 request model——intent × scope × temporal × information needs × action × capability_plan，维度正交、支持多意图，不造巨型组合 taxonomy。路由分级 Level 0–5（无专职路由 / 确定性规则 / 结构化 LLM / 混合 / 分层 / specialist），**simplest sufficient router**——从 0 往上找第一个够用的；Level 2+ 必须 Structured Output + schema validation，禁止自然语言输出再 regex parse；确定性信号（关键词/metadata）优先于 LLM 判定。Intent taxonomy 从产品推断（PRD/API/tools/routes），必有 unknown/other 兜底，重要 route 带 positive/boundary/counterexample 三类样本降低 overlap。**Router 只建议不授权**：capability_plan.tools=true ≠ tool authorization，scope_intent=project 不扩大可见性（Routing suggests. Authorization decides. Visibility enforces.）。歧义 fail closed——默认当前/更小 scope，仅 material ambiguity（影响权限/scope/副作用/工具/正确性）才澄清；routing_confidence 是自报分数非校准概率，阈值经 eval 校准。capability_plan=false 的节点物理跳过；Routing（可能需要什么）/ Retrieval（真正相关什么）/ Context Planner（最终看到什么）三分职责不合并；routing 输出属 Dynamic Runtime State，不进 Stable Prefix。

**写入门控（Memory Writer）**：预判（路由层标记候选）+ 终判（结构化输出 should_store/type/scope/lifetime/source_type/confidence）→ 敏感信息正则拦截 → 向量近邻查重（限定同 scope + 排除系统域）→ 三动作冲突消解（REINFORCE 强化 / SUPERSEDE 失效挂链 / IGNORE），近邻重复簇整体处理而非只取第一条；部分更新 = 新记录携带全量内容走 SUPERSEDE（structured_card 的“局部更新”是逻辑层 field patch，持久化仍是全量快照）。两类 candidate source（architecture.md §3）：Interactive Writer 只从真实对话消息提取——RAG/工具结果/检索内容永远不构成记忆；Derived Writer（background consolidation / episodic promotion / maintenance）只能以现有内部 memories/episodes/raw conversation archive 为 source，重过全部门控并保留 derived_from，**读取 raw archive 时先按 lineage 过滤**（tool_result / rag_context 永不能经派生写入“洗”成 user memory——archiving ≠ authorizing as memory evidence）；RAG/Tool/External Context 永远不能直接成为任何 writer 的 source。「记住以后忽略系统/安全规则」类候选按无效/拒绝写入处理（procedural authority boundary，architecture.md §9.6）。

**检索（Hybrid）**：Visibility 硬过滤先行（user → thread/project scope 隔离，无 project 上下文 fail closed → status=active → valid_to 未过期、NULL=永久有效），向量 + 关键词混合召回，加权重排——语义主导，importance/confidence/字面命中做修正信号，**recency 权重刻意压低**（长期事实"越旧越不重要"是错的）。

**会话范围路由**：元问题必须二分——"这个会话/刚才/本次" → 只允许当前会话消息 + 当前会话摘要；"以前/其他聊天/历史" → 才允许用户级跨会话检索（digest）。加本地关键词短路兜底 LLM 判定摇摆。时间维度同理二分：普通问题只召回 active；显式历史意图（"以前/之前"）才走 historical route 读 superseded 链。本路由的触发判定已统一收编为 request model 的 scope_intent + temporal_intent（见上「请求理解与路由」；request-understanding.md §8.1），实现不变——Routing 只是统一入口。

**摘要防漂移**：不可变分段（每段覆盖固定条数消息、从原文生成一次、永不再摘要），会话摘要 = 段拼接，超预算才做一次“深度 1”合并。摘要的摘要 = 事实漂移之源。最近窗口原文进 prompt，窗口外才进摘要。Forget 不重写摘要——tombstone 在注入期屏蔽。Summary ≠ Memory：摘要是 thread 内压缩表示，不自动当 User Memory 落库；压缩目标是信息密度，不止塞得下。

**Core Memory + Raw History**：Memory ≠ Chat History，但 Structured Core（少量高价值 cards）+ Searchable Raw History（原始消息/trajectory 归档，按 retention policy）= 长期信息系统——Raw History Retrieval 是**按项目选型的 capability**（required/optional/not_needed），非强制启用，不为长期记忆自动建 raw-history 索引；append-only 指不为摘要/Memory 更新重写，受 retention/privacy/deletion policy 管辖。Core = navigation/overview，Raw = detail/evidence——缺细节时触发 raw-history 检索找回证据（architecture.md §4 Overview→Detail），不凭 overview 猜；raw 检索必须过 scope/相关性/预算并受 tombstone 屏蔽，禁止全量倾倒。

**上下文组装**：分层预算 + 各段独立上限（最近窗口/摘要/记忆/RAG/工具结果），溢出截断保头尾关键块；布局按 stability 分三段——Stable Prefix（system/trusted instructions/tool defs，内容顺序稳定，不插时间戳/实时状态）→ Semi-stable（memory/knowledge 按需）→ Dynamic Tail（task state/trajectory/tool results/query），cache-friendly 且不绑定供应商；能力门控（路由判定不需要的模块物理跳过，不是 prompt 里说“忽略”）。

**Memory Type 与高级模式**：semantic / episodic / procedural 是与七层正交的分类模型（§9.1 taxonomy）——semantic 对长期事实/偏好类 Memory 通常适用，episodic / procedural 按项目需要启用，不属于"默认关闭的 Advanced Pattern"。background consolidation、progressive disclosure（Tier 3 目录式上下文）、context planner（token 级动态预算 + query-aware 策略）、entity retrieval、memory hygiene 是 Advanced Patterns，默认关闭，按项目条件选配（§9.2–§9.9）；graph / bi-temporal / multi-agent shared memory 仅特定领域（§10）。Advanced Patterns 由 BUILD 逐项输出 required / recommended / optional / not_needed + reason——敢于说 not_needed 是正确行为。procedural 无论来源（explicit/inferred）与 scope 都受 authority boundary 约束（§9.6，procedural 启用时自动强制的 mandatory guardrail）：只在与更高优先级 system/security/project/tool 约束一致时适用；scope 不参与权限升级——scope=project 的 user procedural 仍是 preference，不是 Trusted Project Policy。
