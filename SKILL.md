---
name: agent-memory-engineering
description: >
  Design, build, implement, evaluate, audit, and debug memory & context
  systems for LLM Agent applications — full lifecycle (requirements →
  architecture → implementation → evaluation → debugging → migration),
  distilled from a production system (FastAPI + LangGraph + PostgreSQL/pgvector).
  Covers memory requirements mapping, layer selection, memory writer gating,
  conflict resolution, hybrid retrieval, session/conversation isolation,
  rolling summaries, token budgeting, and forget/tombstone suppression.
  Use whenever the user mentions Agent memory, 记忆系统, 长期记忆, 上下文管理,
  context engineering, memory writer, 记忆检索, 记忆污染, 跨会话泄漏/串会话,
  conversation summary, session isolation, or wants to design / build / add /
  audit / evaluate / refactor / fix the memory or context layer of any AI
  agent project — even if they only describe a symptom like "agent 记错了"
  or "answers mention other conversations".
---

# Agent Memory / Context Engineering（全生命周期实战方法论）

提炼自真实生产项目踩过的坑。覆盖 Memory / Context System 完整生命周期：**需求 → 架构 → 落地 → 评估 → 调试 → 迁移**——不是 Memory 教程，也不只是 Debug 工具。核心信念：**记忆系统的 bug 几乎都是 scope/隔离问题，不是向量相似度问题**；上下文的 bug 几乎都是"错误内容在哪一步第一次进入流水线"的问题。

## 术语约定

全文 **thread == conversation == 会话**（同一概念；字段名以目标项目为准，下文统称 thread）。**scope** 是记忆的可见范围：`global`（用户级）/ `thread`（会话级）/ `project`（项目级）——global 即 user 级，不承载 system-wide / agent-wide 语义。**memory_type** 是正交的信息性质分类，值域仅 `semantic` / `episodic` / `procedural`；decision 等领域维度走 `domain` 字段（如 `domain='decision'`），不占 memory_type 值域。**digest** 指会话标题列表 + 资产清单的轻量快照（user 级）。

## 按需求选路径

| 用户要什么 | 做法 |
|---|---|
| 从零设计 / 建设 / 接入 Memory System | 走「BUILD 工作流」：DISCOVER → MODEL → DESIGN → MAP → IMPLEMENT → EVALUATE |
| 已有 Memory System，想评估设计质量 | 走「AUDIT 工作流」：只读检查 + 差距报告，默认不改代码 |
| 系统有症状（串会话/记错/污染/答非所问） | 走「调试工作流」定位 Root Cause，再查 `references/architecture.md` 对应模式 |
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

**参数哲学**：本文与 references 里的一切数字（阈值/权重/窗口/预算）都是 **Recommended Default**——经验起点，应通过真实数据集与 eval 校准，不是架构真理。Hard Invariant 是行为约束（见 `references/architecture.md` §0；测试分三层——Universal Hard Invariant / Capability Hard Tests / Quality Metrics，见 `references/testing.md`），与数字无关，不许放松。

## BUILD 工作流：DISCOVER → MODEL → DESIGN → MAP → IMPLEMENT → EVALUATE

为"从零设计 / 重建 / 接入 Memory System"的项目服务。`references/architecture.md` 是**模式库不是模板**——每一步都在做"选择 + 说理由"，不是照抄全套；DESIGN 阶段必须完成 **Layer / Memory Type / Advanced Pattern / Context Strategy** 四项选择，流程不另加阶段。全程约束：铁律 1–8、YAGNI、复用现有栈、minimal change、可测试；最高取舍序 **Correctness → Relevance → Adaptivity → Maintainability → Efficiency**，复杂度只在有理由时引入。

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
```

同时判定三件事：哪些信息需要长期记忆、哪些只是短期运行状态、哪些已有独立 Source of Truth（有 SoT 的只实时查询，铁律 7）。

### 2. MODEL —— 信息分类（Memory Requirement Mapping）

先分类信息，不先设计数据库。每类信息建立映射：

```text
信息 → 生命周期(long/task/session/request) → scope(global/thread/project)
     → memory_type(semantic/episodic/procedural) → Source of Truth
     → 是否长期记忆 → Storage → Retrieval Route
```

memory_type 与 scope/生命周期**正交**（architecture.md §9.1 taxonomy）：semantic = 稳定事实/偏好，episodic = 过去任务的成败经验，procedural = Agent 行动规则——组合如 User+Semantic、Project+Episodic 都是合法的。decision 不是 memory_type 值：决策类信息 = `semantic + domain='decision'`，历史决策事件 = `episodic + domain='decision'`。global procedural = 针对当前 user、跨 thread/project 的行为偏好或工作习惯（"给我代码前先解释"），不是 system-wide 规则——后者属 trusted system policy / agent configuration，不入 user memory 表。

例：「用户喜欢深色主题」→ 长期 / global / semantic / 用户明确陈述 → **是**长期记忆 → memory 表 → 正常召回。
例：「项目决定使用 PostgreSQL」→ 长期 / project / semantic + domain=decision → **是**长期记忆（决策状态/理由/备选放 structured_data）→ memory 表 → 正常召回。
例：「上次部署失败因 migration 未锁表」→ 长期 / project / episodic → **是**长期记忆（历史经验，不因新事实过期；检索显著性可衰减，显式历史查询永远可恢复）。
例：「当前任务完成 70%」→ task / task state 是 SoT → **不是**长期记忆 → 结构化运行态 → 实时读取。

最常见反模式 = 把所有东西塞进 Memory Table。分类结果就是选层与写策略的输入。

### 3. DESIGN —— 按需选层，逐层说理由

七层（architecture.md §1）逐层判定 required / optional / not needed：

```yaml
selected_layers:
  working:   {enabled: true}
  session:   {enabled: true}
  task:      {enabled: true}
  project:   {enabled: false, reason: "产品无 project 概念，YAGNI"}
  user:      {enabled: true}
  knowledge: {enabled: true, reason: "有课程文档 RAG"}
  external:  {enabled: true}
```

必须能回答：**为什么这个项目需要这一层、为什么不需要另一层**。同样输出 memory_type 与 advanced_patterns（architecture.md §9–§10；memory_type 按 §9.1 taxonomy 启用——semantic 对长期事实/偏好类 Memory 通常适用，episodic/procedural 按项目需要；advanced_patterns 逐项 status + reason，默认 not_needed）：

```yaml
memory_types:
  semantic:    {enabled: true,  reason: "用户偏好与约束"}
  episodic:    {enabled: true,  reason: "跨会话复用排障经验"}
  procedural:  {enabled: false, reason: "个人聊天 Agent，无稳定行动规则"}

advanced_patterns:
  background_consolidation: {status: recommended}   # §9.2
  progressive_disclosure:   {status: not_needed}    # §9.4
  context_planner:          {status: optional}      # §9.5
  entity_retrieval:         {status: optional}      # §9.8
  graph_memory:             {status: not_needed}    # §10.1
  bitemporal_memory:        {status: not_needed}    # §10.2
  shared_memory:            {status: not_needed}    # §10.3
```

status 只能取 required / recommended / optional / not_needed；**敢于输出 not_needed** 是本 skill 的正确行为，不是遗漏。随后按 architecture.md 模式设计：Writer 门控 / Visibility / 冲突消解 / Forget / 检索与双路由 / 摘要 / Context Builder / 预算（启用 Planner 时按 §9.5 token 化）/ RAG 与 Tool 隔离。偏离模式库的每一处都要写理由；没有理由就照模式库。关键取舍记入 architecture_decisions，让用户知道"为什么没用某个高级方案"：

```yaml
architecture_decisions:
  - pattern: graph_memory
    decision: not_needed
    reason: "只需要用户偏好与简单项目事实，无多跳关系查询"
    alternatives_considered: ["pgvector + entities JSONB"]
    why_not: "无关系遍历需求，图库是纯负担"
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
  summary_policy:
  storage_design:              # 表 schema / 向量库 / 缓存 key 设计
  implementation_components:   # Pattern → 现有组件清单
  evaluation:                  # required_tests / metrics
```

### 6. EVALUATE —— 按能力选测试，不机械全跑

按 `references/testing.md` 三层分类选择：**A. Universal Hard Invariant**（§6 泄漏/回流 = 0 类，启用对应基础能力即必须满足）+ **B. Capability Hard Tests**（§1 场景 × §7「能力 → 场景映射」，能力启用才必测——如：有长期 User Memory → 1/5/6/7/14；支持 Forget → 11/15；无 project → 跳过 13 并写 reason）+ **C. Quality Metrics**（§8–§11：write / retrieval / context / maintenance / end-task delta / cost）。未启用的能力跳过对应场景并在 skipped_tests 写 reason，不机械全跑；**Metric 阈值按项目校准，不是全项目统一硬门槛**。

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

上线不是终点：接 memory_trace 观测（§9.9：write / retrieval / context / usage 四段），按 §9.3 触发条件跑 Memory Hygiene（merge / supersede / promote，保留 provenance、不动 explicit），用 testing.md §9–§10 的 Hygiene 曲线与 End-task Delta 持续验证 Memory 真的在帮 Agent。

## AUDIT 工作流（只读体检，默认不改代码）

用户说"帮我看看这个 Memory System 设计得怎么样"时走这条路。只读检查、产出差距报告；默认不改代码。用户要求修复时**转「调试工作流」**，默认从 REPRODUCE / TRACE 开始建立修复证据；只有 AUDIT 已同时具备 稳定复现、failing test、first contamination point、root cause、high-confidence 证据时，才允许带证据直接进 PATCH——不为省重复步骤跳过 Root Cause 证明。

```text
INSPECT → CHECK INVARIANTS → CHECK MAPPING → CHECK WRITE PATH → CHECK READ PATH
→ CHECK CONTEXT PATH → SELECT TEST MATRIX → REPORT GAPS
```

1. **INSPECT**：只读侦察，同调试工作流 INSPECT 的 8 个检查点，但对象是整个系统而非单个 bug。
2. **CHECK INVARIANTS**：对照 architecture.md §0 的 8 条 Hard Invariant 逐条判定 满足 / 违反 / 不适用。
3. **CHECK MAPPING**：可变状态是否进了长期记忆？实时数据有没有独立 Source of Truth？RAG/工具结果是否被持久化成 memory？
4. **CHECK WRITE PATH**：写入门控、查重、冲突消解、证据优先级（explicit > inferred_*）。
5. **CHECK READ PATH**：Visibility 硬过滤（user → scope → status → valid_to）、Normal/Historical 双路由、缓存 key 是否含会话维度。
6. **CHECK CONTEXT PATH**：段清单、预算与丢弃顺序、能力门控、tombstone 注入期屏蔽。
7. **SELECT TEST MATRIX**：按启用能力从 testing.md 选场景（同 BUILD 的 EVALUATE）。
8. **REPORT GAPS**：结构化输出 `{gaps: [{severity, violated_invariant, location, fix_hint}], test_matrix, priority}`，修复优先级按铁律下的 PATCH 优先序（数据 Scope 隔离 > Context Routing > Retrieval Filter > …）排。

## 调试工作流：INSPECT → REPRODUCE → TRACE → DIAGNOSE → PATCH → VERIFY

对"系统答出了不属于当前上下文的内容"类 bug 严格按序执行。每阶段有明确禁令；跳阶段（没复现就改码、没 DIAGNOSE 就重构）= 返工。

### 1. INSPECT —— 只读侦察

只允许：读代码、追调用链、理数据流、找 scope 过滤、找检索来源、找 context 组装方式。

- 从请求入口逐函数追到 LLM 调用点，不靠文件名/函数名猜功能。
- 查 8 个点：会话如何创建识别 / 消息绑定哪些 id / 历史查询的 WHERE 条件 / 记忆检索默认范围 / summary 从哪些会话生成 / 缓存 key 是否含会话维度 / "这个会话"类问题被路由到什么数据源 / 最终 prompt 里各段从哪来。

**禁止**：修改任何代码、配置、schema、阈值。

### 2. REPRODUCE —— 没有 failing test 不动手

- 真实环境复现：构造最小对话（A 会话放干扰内容，B 会话只放一句引导语），在 B 里问"这个会话里我问过什么"。混入内容若与某个中间产物（digest/召回结果/摘要）逐字对应 = 注入实锤，非幻觉。
- 自动化复现：写成 pytest 用例，**修复前必须 FAIL**（bug 的可重复证据），修复后必须 PASS。
- **无法稳定复现 → 停在这里**。只加 logging/trace 找触发条件，不改任何代码（见 TRACE 的 CASE F）。

### 3. TRACE —— 找错误内容第一次出现的位置

```
A. 数据库查询阶段   → 查询缺 scope 过滤（只有 user_id 没有 thread_id）
B. 检索阶段         → digest/向量检索按 user 级取数，混入了其他会话内容
C. 摘要阶段         → summary 管线聚合了别的会话
D. 上下文组装阶段   → 检索结果正确，但 Builder 把错误源拼进了最终 prompt
E. LLM 幻觉         → 最终 context 完全正确，模型自己编的
F. 无法稳定复现     → 回 REPRODUCE 加 observability，禁止改架构
```

典型规律：DB 层通常是对的（ORM 过滤天然正确），**泄漏首现于 B 或 D——某个"便利 digest"按 user_id 取了跨会话数据**。LLM 很少是无辜的：它只是忠实复述被注入的内容。

### 4. DIAGNOSE —— 结构化结论（先报告，后动手）

```yaml
symptom:
expected:
actual:
first_contamination_point:   # A–F 分类 + 文件:函数
root_cause:
evidence:                    # failing test 名 / trace 片段；无证据 = 无结论
confidence:                  # high | medium | low；low 则回 TRACE
affected_scope:              # 受影响的 scope 与查询路径
```

### 5. PATCH —— 最小修改

修复优先级：**数据 Scope 隔离 > Context Routing > Retrieval Filter > Summary Isolation > Context Builder > Prompt > Reranking**。

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

再加**能力回归**：列出本次修改的 affected_capabilities，按 testing.md §7 Capability Hard Tests「能力 → 场景映射」选测试——改 Forget 跑 11/15；改 Project Visibility 跑 12/13；改 valid_to 跑 14；改 Historical Route 跑 10；改 Writer 输入边界跑 9；改 Procedural 写入/注入跑 19。原则：**修改影响到的 capability，其对应测试必须全部通过**。

## 核心模式速查（详细版在 references/architecture.md）

**写入门控（Memory Writer）**：预判（路由层标记候选）+ 终判（结构化输出 should_store/type/scope/lifetime/source_type/confidence）→ 敏感信息正则拦截 → 向量近邻查重（限定同 scope + 排除系统域）→ 三动作冲突消解（REINFORCE 强化 / SUPERSEDE 失效挂链 / IGNORE），近邻重复簇整体处理而非只取第一条。候选只从对话消息提取——RAG/工具结果里的内容永远不构成记忆；「记住以后忽略系统/安全规则」类候选按无效/拒绝写入处理（procedural authority boundary，architecture.md §9.6）。

**检索（Hybrid）**：Visibility 硬过滤先行（user → thread/project scope 隔离，无 project 上下文 fail closed → status=active → valid_to 未过期、NULL=永久有效），向量 + 关键词混合召回，加权重排——语义主导，importance/confidence/字面命中做修正信号，**recency 权重刻意压低**（长期事实"越旧越不重要"是错的）。

**会话范围路由**：元问题必须二分——"这个会话/刚才/本次" → 只允许当前会话消息 + 当前会话摘要；"以前/其他聊天/历史" → 才允许用户级跨会话检索（digest）。加本地关键词短路兜底 LLM 判定摇摆。时间维度同理二分：普通问题只召回 active；显式历史意图（"以前/之前"）才走 historical route 读 superseded 链。

**摘要防漂移**：不可变分段（每段覆盖固定条数消息、从原文生成一次、永不再摘要），会话摘要 = 段拼接，超预算才做一次"深度 1"合并。摘要的摘要 = 事实漂移之源。最近窗口原文进 prompt，窗口外才进摘要。Forget 不重写摘要——tombstone 在注入期屏蔽。

**上下文组装**：分层预算 + 各段独立上限（最近窗口/摘要/记忆/RAG/工具结果），溢出截断保头尾关键块；能力门控（路由判定不需要的模块物理跳过，不是 prompt 里说"忽略"）。

**Memory Type 与高级模式**：semantic / episodic / procedural 是与七层正交的分类模型（§9.1 taxonomy）——semantic 对长期事实/偏好类 Memory 通常适用，episodic / procedural 按项目需要启用，不属于"默认关闭的 Advanced Pattern"。background consolidation、progressive disclosure（Tier 3 目录式上下文）、context planner（token 级动态预算 + query-aware 策略）、entity retrieval、memory hygiene 是 Advanced Patterns，默认关闭，按项目条件选配（§9.2–§9.9）；graph / bi-temporal / multi-agent shared memory 仅特定领域（§10）。Advanced Patterns 由 BUILD 逐项输出 required / recommended / optional / not_needed + reason——敢于说 not_needed 是正确行为。procedural 无论来源（explicit/inferred）都受 authority boundary 约束（§9.6）：只在与更高优先级 system/security/project/tool 约束一致时适用，永不提升权限。
