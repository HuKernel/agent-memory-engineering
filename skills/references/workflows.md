# 工作流详解

SKILL.md 定义工作流的**骨架、硬禁令与产出清单**；本文件给出每一步的**执行细则**。进入某工作流后按需读取对应小节。

术语与缩写沿用 SKILL.md：`arch` = `references/architecture.md`，`ru` = `references/request-understanding.md`，`test` = `references/testing.md`，`tpl` = `references/templates.md`。本文件内 `§` 号即对应文件。

---

## §BUILD —— DISCOVER → MODEL → DESIGN → MAP → IMPLEMENT → EVALUATE

为从零设计、重建或接入 Agent Runtime Information Architecture 的项目服务。**不要求三个模块同时重建**：Intent-only task 不强制重建 Memory；Memory-only task 只做必要最小 Request Understanding 设计；Context-only task 不强制新增长期 Memory；Integrated task 三者联合设计。

全程约束：铁律 1–9、YAGNI、复用现有栈、minimal change、可测试；最高取舍序 **Correctness → Relevance → Adaptivity → Maintainability → Efficiency**。

### Design Artifact Protocol（设计持久化）

设计产出不留在对话里——Capability Scope Decision、五类选型产出、`information_mapping`、`routing_strategy` 与最终 blueprint 统一落入项目内 **`AGENT_MEMORY_DESIGN.md`**（单一事实来源：决策 + reason + 变更记录；骨架见 `tpl` §9）。

- 每次进入 BUILD **先检查该文件**再进 Capability Scope Decision：存在 → 先读取，按既有决策续作或增量修订，不重跑全流程、不无故推翻既有决策；不存在 → 随 DESIGN 首批产出新建。
- **文档先于代码**：影响架构的修改先更新该文件再进 IMPLEMENT。
- IMPLEMENT 收尾对账一次，消除文档-实现漂移。
- 调试工作流 PATCH / AUDIT 后的修复若改变设计决策，同步更新对应条目。

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
  raw_history_retention:                 # raw history 保留策略
  supports_user_forget:                  # 是否支持 forget_for_inference
  requires_hard_delete_or_privacy_erasure:  # 是否要求 hard-delete / privacy erasure
model_context:
  context_window:                        # 模型 context window
  prefix_cache_supported:                # provider 是否支持 prefix cache
routing_requirements:
  intent_sources:                        # 可推断 intent space 的来源（PRD/API/tools/现有 routes/user journeys）
  existing_router:                       # 已有路由实现（none/rules/llm）
  specialist_agents:                     # 是否存在真正需要独立 prompt/工具/权限的 specialist
```

这五组输入直接决定 DESIGN 阶段的 Raw History Retrieval、Context Stability / Cache Strategy、Retention / Erasure 选型与 Routing Strategy（`ru` §2–§3，taxonomy 来自产品、禁止内置通用分类、必有 unknown 兜底）。

同时判定三件事：哪些信息需要长期记忆、哪些只是短期运行态、哪些已有独立 Source of Truth（有 SoT 的只实时查询，铁律 7）。

### 2. MODEL —— Runtime Requirement Modeling（capability-selective）

先建模，不先设计数据库。核心原则 **No consumer → No field**，不强制全字段输出。

**A. Request Modeling**（request_understanding = required / relevant 时）：字段以 `ru` §1 Recommended Schema 为准（`primary_intent` / `scope_intent` / `temporal_intent` / `information_needs` / `action_need` / `capability_plan` / `ambiguity` / `risk` / `routing_confidence`），按项目裁剪——**字段必须有消费方**（capability_plan / Context Planner / routing_trace），无消费方不建（铁律 5 的同型约束）。单 Agent 无历史查询 → scope/temporal 可退化为 needs_history 一个布尔；无工具无副作用 → 删 risk / action_need。

**B. Information / Memory Modeling**（memory = required / relevant 时）——每类信息建立映射（模板 `tpl` §3）：

```text
信息 → 生命周期(long/task/session/request) → scope(global/thread/project)
     → memory_type(semantic/episodic/procedural) → representation(表示策略，arch §2)
     → Source of Truth → 是否长期记忆 → Storage → Retrieval Route
```

- **memory_type 与 scope/生命周期正交**（arch §9.1）：semantic = 稳定事实/偏好，episodic = 过去任务的成败经验，procedural = Agent 行动规则——User+Semantic、Project+Episodic 等组合都合法。
- **decision 不是 memory_type 值**：决策类信息 = `semantic + domain='decision'`，历史决策事件 = `episodic + domain='decision'`。
- **global procedural** = 针对当前 user、跨 thread/project 的行为偏好（"给我代码前先解释"），不是 system-wide 规则——后者属 trusted system policy / agent configuration，不入 user memory 表。
- **Representation Strategy**（arch §2，设计决策维度，不是 DB 字段）：五种表示 `atomic_note` / `enhanced_note` / `structured_card` / `rich_contextual_card` / `raw_history_reference`，选型判据见 arch §2。**Representation 不绑定 memory_type**——由信息复杂度、更新频率、关系复杂度、检索方式、token cost 共同决定。

**Capability-selective 规则**：

```text
Request/Intent-only project:  Request Modeling = required；Memory Modeling = only if relevant
Memory-heavy project:         Memory Modeling = required；Request Modeling = minimal（只建 routing 必要输入）
Context-only optimization:    只建 Context Planner 真正需要的 request dimensions
Full Agent Runtime:           Request Modeling + Information/Memory Modeling
```

最常见反模式 = 把所有东西塞进 Memory Table。分类结果就是选层与写策略的输入。

### 3. DESIGN —— 按需选层，逐层说理由

**五类产出缺一不可**（模板 `tpl` §2）：

| 产出 | 判读依据 | status 词表 |
|---|---|---|
| `selected_layers` | 七层（arch §1） | required / optional / not_needed |
| `memory_types` | semantic / episodic / procedural（arch §9.1） | required / recommended / optional / not_needed |
| `representation_strategy` | 五种表示（arch §2） | 同上 |
| `advanced_patterns` | arch §9.2–§9.9 | 同上 |
| `routing_strategy` | 分级 + schema + taxonomy（ru §2 / §1 / §3） | level 0–5 + reason |

- **每项必须带 reason，不允许只有 status 的输出**；敢于输出 not_needed 是正确行为，不是遗漏。
- 唯一例外：arch §9.6——procedural memory 启用时其 authority boundary **自动强制**（mandatory guardrail），不参与选配、不能关闭。
- 五类写在一起，避免分头填写导致互相矛盾。

**Structured Core vs Raw History**（arch §1，**Core Design Question**）：每个 BUILD 必答三问——是否保留 raw source？是否需要 searchable raw history？是否需要 Overview → Detail？——答案取 required / optional / not_needed。

- 简单 preference chatbot：Core required / Searchable Raw History not_needed（YAGNI——**不为长期记忆自动建 raw-history 索引**）。
- Coding / Research Agent：Raw History Retrieval recommended 或 required。
- Core = navigation/overview，Raw = detail/evidence；普通问题走 active memory，detail lookup / 显式历史意图才回 raw（双路由不变）。
- raw 保留受 retention / privacy / deletion policy 管辖——append-only 指不为摘要/Memory 更新重写，不表示不可删除。

**Context Stability**（arch §6 / §9.5）：BUILD 输出 stable_prefix / semi_stable / dynamic_tail 分段与 cache_strategy（Context Architecture Decision，不强制新增 runtime schema）；provider 无可利用 prefix cache 时保留 stable-prefix 布局、cache benefit 标 not_applicable。

**Routing Strategy**（ru §1–§7）：BUILD 输出路由分级、request model 裁剪与 intent taxonomy——**simplest sufficient router**，从 Level 0 往上找第一个够用的，不从 Level 3 起步；request model 按项目裁剪，字段必须有消费方，禁止全字段堆砌。铁律 9 在此落地：capability_plan 只建议不授权，ambiguity fail closed，routing 输出不进 Stable Prefix（ru §8.4）。

**其余机制**按 arch 模式设计：Writer 门控 / Visibility / 冲突消解 / Forget / 检索与双路由（含 Raw History Retrieval）/ 摘要 / Context Builder（含三段布局）/ 预算（启用 Planner 时按 §9.5 token 化 + 双目标）/ RAG 与 Tool 隔离。**偏离模式库的每一处都要写理由；没有理由就照模式库。** 关键取舍记入 `architecture_decisions`（模板 `tpl` §4），覆盖全部 not_needed 的高级模式与偏离模式库之处。

### 4. MAP —— 映射到现有技术栈

先识别现有栈（语言 / Agent 框架 / DB / 向量库 / 缓存），再把 Pattern → Existing Component，**优先复用**，不为符合本 skill 新建重复基础设施：

```text
Task Memory          → LangGraph State / 请求 State
User Memory          → 现有 PostgreSQL 表 + pgvector
Knowledge Retrieval  → 现有 Qdrant collection / ES 索引
Short-lived cache    → Redis
```

FastAPI + LangGraph + PostgreSQL/pgvector 只是参考实现，不是要求。

**Memory Interface Pattern**（接口形态选型，决定铁律 9 的 enforcement point 在哪层执行）：

| 形态 | 做法 | 门控 / 隔离责任 |
|---|---|---|
| pipeline-injected | 检索管线按 visibility 过滤后注入 context（默认模式） | Writer 门控与 Visibility 硬过滤全在管线，模型只消费 |
| tool-based | 记忆读写暴露为工具（memory_view / create / update / delete 类），Agent 自主调用 | 写入仍必须过 Writer 门控（candidate 不因来源是模型而免检）；Visibility 硬过滤在工具返回前强制执行 |
| platform-managed | 宿主平台内置记忆与上下文管理（自带 memory tool / context editing 类机制） | 部分门控移交平台；采用前必须逐条核对平台机制与 Hard Invariant 的差异（scope 隔离、forget 语义、untrusted content 边界），平台覆盖不了的自行补层 |

接口形态不改变铁律：任何形态下 "记住 X" 只产生 memory_write_candidate（铁律 9）、untrusted external content 永不直接成 memory（arch §0.7）、Visibility 硬过滤不可降级为 prompt 约定（铁律 4）。

### 5. IMPLEMENT —— 落地

**Host capability 语义**：按宿主实际能力执行——host 提供文件读写 / shell / 测试运行能力时直接执行；某项能力不可用时对该项降级为 implementation-ready 计划，不虚构执行结果。

- **有代码**：主动读项目找 request entry、LLM 调用链、message storage、persistence、vector retrieval、context builder、summary、tests → 输出 implementation plan（Schema/Model、Writer、Retrieval、Context Builder、Summary、Routing、Tests、Migration）→ 直接落地实现。仍守 minimal change / reuse / YAGNI。
- **无代码（只有产品需求）**：输出 Implementation-ready Blueprint（`memory_system_blueprint`，模板 `tpl` §5），工程师可直接开工。

**自主执行边界**：用户已明确请求"设计并实现 / 帮我把 Memory 做好 / 接入 Memory / 直接改"时，DISCOVER → EVALUATE 连续完成，**不在 DESIGN 后默认停下二次确认**。只有这些情况必须停下来问：destructive migration、数据删除、不可逆 schema change、涉及生产数据的大规模迁移、两种方案都会显著改变产品行为且现有上下文无法裁决、缺失会改变架构的关键业务信息。新增 service/repository/memory writer、调整 context builder、加测试、加普通 schema field——属原始请求范围内的正常实现，无需再确认。

### 6. EVALUATE —— 按能力选测试，不机械全跑

按 `test` 三层选（模板 `tpl` §6）：

- **A. Universal Hard Invariant**（test §6 泄漏/回流 = 0 类）——启用对应基础能力即必须满足。
- **B. Capability Hard Tests**（test §1 场景 × §7 能力→场景映射）——能力启用才必测。有长期 User Memory → 1/5/6/7/14；支持 Forget → 11/15；启用 Request Understanding / Router → 24–31。
- **C. Quality Metrics**（test §8–§11）——write / retrieval / routing / context / maintenance / end-task delta / cost。

未启用的能力跳过对应场景并在 `skipped_tests` 写 reason，不机械全跑。**Metric 阈值按项目校准，不是全项目统一硬门槛**——需要外部数据集校准 / 横向可比基线时按 test §12 公开基准映射（LongMemEval / LoCoMo）选子集，基准不改变 Hard Invariant。

### 7. 运行期 —— OBSERVE / MAINTAIN

上线不是终点：接 memory_trace 观测（arch §9.9：routing / write / retrieval / context / usage 五段；routing 段见 ru §10），按 arch §9.3 触发条件跑 Memory Hygiene（merge / supersede / promote，保留 provenance、不动 explicit），用 test §8 Routing Quality 与 §9–§10 的 Hygiene 曲线、End-task Delta 持续验证 Memory 真的在帮 Agent。

---

## §MIGRATION —— 存量系统改造

用户要把已有记忆/上下文系统迁到新架构、或已有 schema 需要演进时走这条路。三阶段划分见 arch §8「迁移哲学」——**Phase 1 正确性**（写/读路径的 scope 隔离、冲突证据优先级、重复清理，零 Schema 变更）→ **Phase 2 表达力**（project/task 等新维度，**等产品层出现对应概念再建**）→ **Phase 3 预算**（按问题类型分档 token 预算）。

1. **INSPECT 现状**：读现有 schema 与读写路径，判定当前实现落在哪一 Phase 的哪一步——已有系统的问题通常不是缺能力，而是缺**隔离**（先做 Phase 1）。
2. **对齐目标架构**：按 BUILD 的 Capability Scope Decision + DESIGN 判定目标形态（scope 枚举、memory_type、representation、routing），产出新旧映射表；只做 Phase 2 中**产品已存在对应概念**的维度。
3. **迁移执行**：走幂等补列（`ADD COLUMN IF NOT EXISTS`）。**旧行 NULL 不得自动解释为 global**——`scope=NULL` 是未知 scope，`scope='global' AND scope_id=NULL` 才是合法 global memory；旧 schema 历史定义能明确证明 NULL==global 的，显式 backfill；**证明不了的 fail closed**——不参与正常召回，直到完成迁移/归类。不为 backward compatibility 扩大可见范围。
4. **VERIFY**：按 test §7 能力→场景映射跑受影响能力的硬测试（隔离类必跑 2/12/13/15），确认迁移未扩大可见范围、合法路径未误伤。

**停止条件**：涉及生产数据的大规模迁移、数据删除、不可逆 schema change——先说明影响面与回滚方案，等用户确认再动手。

---

## §AUDIT —— 只读体检

用户要求审查现有 Agent 的 request understanding、intent routing、memory 或 context architecture 时走这条路。**只读检查、产出差距报告；默认不改代码。**

用户要求修复时**转调试工作流**，默认从 REPRODUCE / TRACE 开始建立修复证据；只有 AUDIT 已同时具备稳定复现、failing test、first contamination point、root cause、high-confidence 证据时，才允许带证据直接进 PATCH——不为省重复步骤跳过 Root Cause 证明。

```text
INSPECT → CHECK INVARIANTS → CHECK MAPPING → CHECK ROUTING PATH → CHECK WRITE PATH
→ CHECK READ PATH → CHECK CONTEXT PATH → SELECT TEST MATRIX → REPORT GAPS
```

1. **INSPECT**：只读侦察，同调试工作流 INSPECT 的 8 个检查点，但对象是整个系统而非单个 bug。
2. **CHECK INVARIANTS**：对照 arch §0 的 10 条 Hard Invariant 逐条判定 满足 / 违反 / 不适用（含 §0.9 Routing ≠ Authorization、§0.10 歧义 fail closed——启用路由的系统必查）。
3. **CHECK MAPPING**：可变状态是否进了长期记忆？实时数据有没有独立 Source of Truth？RAG/工具结果是否被持久化成 memory？
4. **CHECK ROUTING PATH**（ru）——11 项：
   - request model 是否按项目裁剪（无消费方字段 = 反模式）？
   - intent taxonomy 是否来自产品能力而非内置通用分类？unknown / other 兜底是否存在？
   - scope / temporal 判定是否正确？ambiguity 是否 fail closed（§0.10）？
   - capability_plan 是否与 request model 一致？false capability 是否物理跳过？
   - routing 是否错误扩大 visibility？router 是否错误承担 authorization（§0.9）？
   - routing output 是否误入 Stable Prefix？
   - handoff / specialist 是否过度设计（intent label ≠ Agent）？
   - 职责边界：**Routing Path 查"为什么选择这些能力"，Read Path 查"这些能力如何安全读取数据"**——不重复 Memory Visibility 检查。
5. **CHECK WRITE PATH**：写入门控、查重、冲突消解、证据优先级（explicit > inferred_*）。
6. **CHECK READ PATH**：Visibility 硬过滤（user → scope → status → valid_to）、Normal/Historical 双路由、缓存 key 是否含会话维度。
7. **CHECK CONTEXT PATH**：段清单、预算与丢弃顺序、能力门控、tombstone 注入期屏蔽。
8. **SELECT TEST MATRIX**：按启用能力从 test 选场景（同 BUILD 的 EVALUATE）。
9. **REPORT GAPS**：结构化输出（模板 `tpl` §8）`{gaps: [{severity, violated_invariant, location, fix_hint}], test_matrix, priority}`，修复优先级按 PATCH 优先序（Authorization / Scope Isolation > Request Routing > Retrieval Filter > …）排。

---

## §DEBUG —— INSPECT → REPRODUCE → TRACE → DIAGNOSE → PATCH → VERIFY

对"系统答出了不属于当前上下文的内容""意图识别 / 路由 / 能力激活错误"类 bug 严格按序执行。每阶段有明确禁令；**跳阶段（没复现就改码、没 DIAGNOSE 就重构）= 返工**。

### 1. INSPECT —— 只读侦察

只允许：读代码、追调用链、理数据流、找 scope 过滤、找检索来源、找 context 组装方式。

- 从请求入口逐函数追到 LLM 调用点，不靠文件名/函数名猜功能。
- 查 8 个点：会话如何创建识别 / 消息绑定哪些 id / 历史查询的 WHERE 条件 / 记忆检索默认范围 / summary 从哪些会话生成 / 缓存 key 是否含会话维度 / "这个会话"类问题被路由到什么数据源 / 最终 prompt 里各段从哪来。

**禁止**：修改任何代码、配置、schema、阈值。

### 2. REPRODUCE —— 没有 failing test 不动手

- **真实环境复现**：构造最小对话（A 会话放干扰内容，B 会话只放一句引导语），在 B 里问"这个会话里我问过什么"。混入内容若与某个中间产物（digest/召回结果/摘要）逐字对应 = 注入实锤，非幻觉。
- **自动化复现**：写成 pytest 用例，**修复前必须 FAIL**（bug 的可重复证据），修复后必须 PASS。
- **无法稳定复现 → 停在这里**。只加 logging/trace 找触发条件，不改任何代码（见 TRACE 的 CASE F）。

### 3. TRACE —— 找错误第一次出现的位置

```text
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

典型规律：DB 层通常是对的（ORM 过滤天然正确），**泄漏首现于 B 或 D——某个"便利 digest"按 user_id 取了跨会话数据**。LLM 很少是无辜的：它只是忠实复述被注入的内容。

启用路由的系统先判 R——**Routing 错误是独立 first failure point**：用户明确问"这个会话里……"而 Router 产出 user + historical，first failure point 是 R 不是 B，即使 Retrieval 忠实执行了错误 route（downstream symptom 不改判分类）。Routing 根因的修复优先补确定性规则 / fail-closed 默认值（ru §4/§5），不是调检索权重。

### 4. DIAGNOSE —— 结构化结论（先报告，后动手）

模板见 `tpl` §7：

```yaml
symptom:
expected:
actual:
first_contamination_point:   # R / A–F 分类 + 文件:函数
root_cause:
evidence:                    # failing test 名 / trace 片段；无证据 = 无结论
confidence:                  # high | medium | low；low 则回 TRACE
affected_scope:              # 受影响的 scope 与查询路径
routing_evidence:            # 仅 first_contamination_point=R 时输出
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
2. 跨会话隔离：test 场景 2（B 会话零泄漏）；
3. 合法跨会话不误伤：显式问"以前聊过什么"仍能召回；
4. 用户级 global memory 不误伤："我通常喜欢什么"仍工作；
5. superseded 记忆不回流 normal route：场景 1；
6. 重复记忆不重复召回：场景 7；
7. context token 有界：场景 4。

**能力回归**：列出本次修改的 affected_capabilities，按 test §7「能力 → 场景映射」选测试——改 Forget 跑 11/15；改 Project Visibility 跑 12/13；改 valid_to 跑 14；改 Historical Route 跑 10；改 Writer 输入边界跑 9；改 Procedural 写入/注入跑 19；改 Raw History Retrieval 跑 20/21；改 Derived Writer / lineage 过滤跑 22；改 Context Stability 跑 23；改 Router baseline 跑 24–28；改 multi-intent 跑 29；改 routing 注入防护跑 30；改语义/LLM router 跑 31 + test §8 Routing Quality。原则：**修改影响到的 capability，其对应测试必须全部通过**。
