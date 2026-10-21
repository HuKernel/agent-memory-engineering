---
name: agent-memory-engineering
description: >
  Design, build, evaluate, audit, and debug request-understanding, memory and
  context systems for LLM Agent applications. Covers the Agent Runtime
  Information Architecture (request understanding & intent routing, memory
  layers, context assembly) across the full lifecycle: requirements →
  architecture → implementation → evaluation → debugging → migration. Use
  whenever the user mentions agent memory, 记忆系统, 长期记忆, 上下文管理,
  context engineering, intent routing, 意图识别, 意图路由, request
  understanding, agent runtime architecture, memory writer, 记忆检索, 记忆污染,
  跨会话泄漏, 串会话, conversation summary, session isolation, or reports
  symptoms like "agent 记错了" or "answers mention other conversations".
---

# Agent Runtime Information Architecture：Request Understanding + Memory / Context Engineering

提炼自真实生产项目踩过的坑。覆盖 Agent Runtime 信息架构三大支柱的完整生命周期：**Request Understanding & Routing（请求怎么被理解与调度）+ Memory（跨 session 记什么、怎么读写）+ Context（每个决策点让模型看到什么）**——需求 → 架构 → 落地 → 评估 → 调试 → 迁移。运行时最高原则：**Understand → Route → Retrieve → Plan Context → Act → Update → Evaluate**（完整管线图见 `arch` 开篇）。

核心信念：**记忆系统的 bug 几乎都是 scope/隔离问题，不是向量相似度问题**；上下文的 bug 几乎都是"错误内容在哪一步第一次进入流水线"的问题；路由的 bug 几乎都是"把理解降级成单标签分类"或"把路由建议当权限"的问题。

本文是**路由与约束**：告诉 Agent 走哪条工作流、产出什么、什么时候停；各机制的实现细节与判读口径在 `references/`，细节与本文冲突时以 references 为准。

## 术语约定

| 术语 | 含义 |
|---|---|
| **thread** == conversation == 会话 | 同一概念；字段名以目标项目为准，下文统称 thread |
| **scope** | 记忆的可见范围：`global`（用户级）/ `thread`（会话级）/ `project`（项目级）。global 即 user 级，不承载 system-wide / agent-wide 语义 |
| **authority** | procedural instruction 的行为优先级，与 scope **正交**——scope=project 不自动等于 Project Hard Rule（arch §9.6） |
| **memory_type** | 正交的信息性质分类，值域仅 `semantic` / `episodic` / `procedural`；领域维度走 `domain` 字段（如 `domain='decision'`），不占 memory_type 值域 |
| **digest** | 会话标题列表 + 资产清单的轻量快照（user 级） |
| **Request Understanding & Routing** | 请求进入后的理解与调度层，产出多维 **request model**（intent × scope × temporal × information needs × action × capability_plan，维度正交）；`scope_intent` / `temporal_intent` 收编现有会话范围路由与 Normal/Historical 双路由的触发判定（实现不变）；请求侧 `scope_intent.level=user` 即存储侧 scope `global` |
| **Router** | 只产出建议、不授权：Routing suggests. Authorization decides. Visibility enforces. |

## 按需求选路径

> **文件缩写**（全文通用）：`arch` = `references/architecture.md`，`ru` = `references/request-understanding.md`，`test` = `references/testing.md`，`tpl` = `references/templates.md`，`wf` = `references/workflows.md`。引用写成 `arch §9.6` 形式——**跨文档引用必须带文件名**，裸 `§N` 会被误读为本文章节。

| 用户要什么 | 做法 |
|---|---|
| 不知道怎么理解请求 / 识别意图 / 做能力路由 | 读 `ru`；BUILD（Capability Scope: request_understanding=required） |
| 不知道怎么设计长期记忆 / 跨会话恢复 | Memory BUILD：MODEL 的 Information/Memory Modeling + DESIGN 选层选型 |
| 怎么做 Context Management / token budget / summary / compression / stable prefix | Context BUILD：DESIGN 的 Context Strategy / Context Planner（arch §5–§6、§9.5） |
| Agent Runtime 整体设计（Intent + Memory + Context） | Integrated BUILD：三支柱联合设计（先做 Capability Scope Decision） |
| 已有架构，想评估设计质量 | 走「AUDIT 工作流」：只读检查 + 差距报告，默认不改代码 |
| 系统有症状（串会话/记错/污染，或 意图识别错误/路由错误/工具选错/能力误激活/错误跨会话历史检索） | 走「调试工作流」定位 Root Cause（CASE R / A–F），再查对应 reference |
| 要把旧记忆系统迁到新架构 | 走「MIGRATION 工作流」 |
| 要写测试 / 验收 / 评估指标 | 读 `test`，按项目能力选场景 |
| 维护者自查触发质量 / 工作流是否漂移 | 跑 `evals/evals.md` 的触发正负样本与三工作流 golden trace |

**references 导航**：`arch` = Memory/Context 模式库（§0 Hard Invariant / §1 七层与 Core-Raw / §2 Representation / §3 Writer / §4 检索 / §5 Forget 与摘要 / §6 Context / §8 迁移 / §9 taxonomy 与 Advanced / §10 特定领域）；`ru` = 请求理解与路由模式库（§1 request model / §2 Level 0–5 / §3 taxonomy / §4–§5 混合路由与 fail-closed / §8 收编表 / §10 trace）；`test` = 评估矩阵（31 场景、三层体系、能力→场景映射、公开基准校准 §12）；`tpl` = 产出模板库；`wf` = 工作流执行细则。已知主题按 § 直读；不确定位置按关键词 Grep（`tombstone` / `scope_intent` / `fail closed` / `supersede` / `capability_plan`）。

## 铁律（冲突时按此序裁决）

1. 正确性 > 防记忆污染 > 上下文相关性 > 可维护性 > 性能 > Token 成本。
2. Memory ≠ 聊天记录；Context ≠ 全部历史。写库前必须过门控，进 prompt 前必须过预算。
3. **先复现、先 trace，再改代码**。Root Cause 未定位前禁止重构。
4. 会话/scope 隔离错误，禁止用"调 embedding 相似度阈值 / 换向量库"来修——那是把路由错误当检索问题治。（= arch §0.4）
5. 没有 UI/API 消费方的 Schema 不要建（projects/tenant/memory_versions 表大多是 YAGNI；版本史用 `superseded_by` 链表达）。
6. 模型推断不得覆盖用户明确陈述（explicit > inferred_strong > inferred_weak）；写入门控 LLM 判定失败时默认不写，宁漏勿错。（= arch §0.2 + §0.5）
7. 临时/可变状态（进度百分比、资产清单、本周在哪）不写入长期记忆——实时查询才是 Source of Truth。（= arch §0.7）
8. 被 Forget 的事实不得回流最终 prompt：tombstone 在注入期屏蔽旧摘要/digest/缓存里的原话（arch §5）；仅靠"以记忆段为准"的仲裁声明不够。（= arch §0.8）
9. **Routing 只建议、不授权**：路由结果不构成 tool authorization、不扩大 Memory visibility；intent 歧义 fail closed——默认解析到当前/更小 scope，绝不扩大可见范围；"记住 X" 只产生 memory_write_candidate，必须仍过 Writer 门控。（= arch §0.9 + §0.10）

> **铁律 ↔ Hard Invariant 是两份正交清单，不是父子关系**：铁律是**裁决序**（做取舍时先看这条），arch §0 的 10 条是**技术细则**（实现时逐条判定）。上列括号内标出的是直接对应的 §0 条目；未标出的铁律（1/2/3/5）在 §0 中没有对应条目，反之 §0.1/§0.3/§0.6 也没有对应的铁律。**按 §0.N 查铁律编号会查错**——查 §0 用 §0，查铁律用本文「铁律」节。

**参数哲学**：本文与 references 里的一切数字（阈值/权重/窗口/预算）都是 **Recommended Default**——经验起点，应通过真实数据集与 eval 校准，不是架构真理。Hard Invariant 是行为约束（arch §0），与数字无关，不许放松。

## 工作流总览

四个工作流共用同一套硬约束（铁律 1–9、YAGNI、复用现有栈、minimal change、可测试）。**执行细则见 `wf`**（进入某工作流后按需读取对应小节）；产出模板见 `tpl`。

| 工作流 | 触发 | 阶段 | 硬约束 |
|---|---|---|---|
| **BUILD** | 从零设计 / 重建 / 接入 Agent Runtime | DISCOVER → MODEL → DESIGN → MAP → IMPLEMENT → EVALUATE | 不要求三支柱同时重建；DESIGN 五类产出缺一不可；自主执行，不在 DESIGN 后默认停 |
| **MIGRATION** | 存量记忆系统改造 / schema 演进 | INSPECT → 对齐目标 → 迁移执行 → VERIFY | 幂等补列；旧行 NULL 不自动当 global；大规模迁移先确认 |
| **AUDIT** | 评估现有架构质量 | INSPECT → CHECK ×6 → SELECT TEST MATRIX → REPORT GAPS | **只读，默认不改代码**；修复转调试工作流 |
| **DEBUG** | 系统有症状（串会话 / 记错 / 路由错） | INSPECT → REPRODUCE → TRACE → DIAGNOSE → PATCH → VERIFY | **没复现不改码；没 DIAGNOSE 不重构**；最小修改 |

### BUILD —— 从零设计 / 重建 / 接入 Agent Runtime

**阶段**：DISCOVER → MODEL → DESIGN → MAP → IMPLEMENT → EVALUATE（+ 运行期 OBSERVE / MAINTAIN）。**详细阶段说明见 `wf` §BUILD。**

**三个关键产出**：

1. **Capability Scope Decision**——BUILD 第一个动作，判断本任务需要 request_understanding / memory / context 哪几项（`required` / `relevant` / `not_needed` + reason）。防止 Intent-only 被强推整套 Memory、Context-only 被强推长期 Memory。模板：`tpl` §1。
2. **DESIGN 五类产出**——`selected_layers` / `memory_types` / `representation_strategy` / `advanced_patterns` / `routing_strategy`，**每项必带 reason**；敢于输出 not_needed 是正确行为。arch §9.6（procedural authority boundary）随 procedural 启用自动强制，不参与选配。模板：`tpl` §2。
3. **Design Artifact Protocol**——设计产出统一落入项目内 `AGENT_MEMORY_DESIGN.md`（单一事实来源：决策 + reason + 变更记录）。**每次进入 BUILD 先检查该文件**：存在 → 按既有决策续作或增量修订，不重跑全流程；不存在 → 随 DESIGN 首批产出新建。文档先于代码，IMPLEMENT 收尾对账一次；PATCH / AUDIT 后的修复若改变设计决策，同步更新。

**硬约束**：

- `arch` 是 Memory/Context 的**模式库不是模板**，`ru` 是请求理解与路由的模式库——每一步都在做"选择 + 说理由"，不是照抄全套。
- 最高取舍序 **Correctness → Relevance → Adaptivity → Maintainability → Efficiency**，复杂度只在有理由时引入。
- **自主执行边界**：用户已明确请求"设计并实现 / 帮我把 Memory 做好 / 接入 Memory / 直接改"时，DISCOVER → EVALUATE 连续完成，**不在 DESIGN 后默认停下二次确认**。必须停下来问的情况只有：destructive migration、数据删除、不可逆 schema change、涉及生产数据的大规模迁移、两种方案都会显著改变产品行为且现有上下文无法裁决、缺失会改变架构的关键业务信息。新增 service/repository/memory writer、调整 context builder、加测试、加普通 schema field——属原始请求范围内的正常实现，无需再确认。
- **Host capability 语义**：host 提供文件读写 / shell / 测试运行能力时直接执行；某项能力不可用时对该项降级为 implementation-ready 计划，不虚构执行结果。

**完成定义（Definition of Done）**——六项全过才算交付，缺一项回到对应阶段：

1. `AGENT_MEMORY_DESIGN.md` 已落盘，且与最终实现一致（IMPLEMENT 后对账过）；
2. Capability Scope Decision 与 DESIGN 五类产出逐项 status + reason，无裸 status；
3. `architecture_decisions` 覆盖全部 not_needed 的高级模式与偏离模式库之处；
4. `evaluation_plan` 完整：`skipped_tests` 逐项带 reason，`required_tests` 全绿或明确记录未跑原因；
5. 铁律 1–9 与 `arch` §0 Hard Invariant 逐条复核通过（启用对应能力的尤甚）；
6. 无代码项目：Implementation-ready Blueprint 完整，工程师可直接开工。

**EVALUATE 三层选测**（`test`）：**A. Universal Hard Invariant**（§6 泄漏/回流 = 0 类，启用对应能力即必须满足）+ **B. Capability Hard Tests**（§1 场景 × §7 能力→场景映射，能力启用才必测——有长期 User Memory → 1/5/6/7/14；支持 Forget → 11/15；启用 Router → 24–31）+ **C. Quality Metrics**（§8–§11）。未启用的能力跳过并在 `skipped_tests` 写 reason，不机械全跑；**Metric 阈值按项目校准，不是全项目统一硬门槛**——需要横向可比基线时按 `test` §12 公开基准（LongMemEval / LoCoMo）选子集，基准不改变 Hard Invariant。

**运行期（IMPLEMENT 之后）**：接 memory_trace 观测（`arch` §9.9：routing / write / retrieval / context / usage 五段；routing 段见 `ru` §10），按 §9.3 触发条件跑 Memory Hygiene（merge / supersede / promote，保留 provenance、不动 explicit），用 `test` §8 Routing Quality 与 §9–§10 的 Hygiene 曲线、End-task Delta 持续验证 Memory 真的在帮 Agent。

### MIGRATION —— 存量系统改造

用户要把已有记忆/上下文系统迁到新架构、或已有 schema 需要演进时走这条路。三阶段划分见 `arch` §8「迁移哲学」——**Phase 1 正确性**（写/读路径的 scope 隔离、冲突证据优先级、重复清理，零 Schema 变更）→ **Phase 2 表达力**（project/task 等新维度，**等产品层出现对应概念再建**）→ **Phase 3 预算**（按问题类型分档 token 预算）。执行细则见 `wf` §MIGRATION。

**硬约束**：迁移走幂等补列（`ADD COLUMN IF NOT EXISTS`）；**旧行 NULL 不得自动解释为 global**——`scope=NULL` 是未知 scope，`scope='global' AND scope_id=NULL` 才是合法 global memory；旧 schema 历史定义能明确证明 NULL==global 的显式 backfill，**证明不了的 fail closed**（不参与正常召回）；不为 backward compatibility 扩大可见范围。涉及生产数据的大规模迁移、数据删除、不可逆 schema change——先说明影响面与回滚方案，等用户确认再动手。

### AUDIT —— 只读体检（默认不改代码）

用户要求审查现有 Agent 的 request understanding、intent routing、memory 或 context architecture（如"帮我看看这个 Memory System / 路由层设计得怎么样"）时走这条路。**只读检查、产出差距报告；默认不改代码。**

用户要求修复时**转「调试工作流」**，默认从 REPRODUCE / TRACE 开始建立修复证据；只有 AUDIT 已同时具备稳定复现、failing test、first contamination point、root cause、high-confidence 证据时，才允许带证据直接进 PATCH——不为省重复步骤跳过 Root Cause 证明。

阶段与 11 项 Routing Path 检查清单见 `wf` §AUDIT。差距报告格式见 `tpl` §8。

### DEBUG —— INSPECT → REPRODUCE → TRACE → DIAGNOSE → PATCH → VERIFY

对"系统答出了不属于当前上下文的内容""意图识别 / 路由 / 能力激活错误"类 bug 严格按序执行。**每阶段有明确禁令；跳阶段（没复现就改码、没 DIAGNOSE 就重构）= 返工。** 各阶段执行细则见 `wf` §DEBUG。

**各阶段硬约束**：

- **INSPECT**——只允许读代码、追调用链、理数据流、找 scope 过滤、找检索来源、找 context 组装方式。**禁止修改任何代码、配置、schema、阈值。** 查 8 个点：会话如何创建识别 / 消息绑定哪些 id / 历史查询的 WHERE 条件 / 记忆检索默认范围 / summary 从哪些会话生成 / 缓存 key 是否含会话维度 / "这个会话"类问题被路由到什么数据源 / 最终 prompt 里各段从哪来。
- **REPRODUCE**——**没有 failing test 不动手**。真实环境复现构造最小对话（A 会话放干扰内容，B 会话只放一句引导语），混入内容若与某个中间产物（digest/召回结果/摘要）逐字对应 = 注入实锤，非幻觉。自动化复现写成 pytest，**修复前必须 FAIL**，修复后必须 PASS。**无法稳定复现 → 停在这里**，只加 logging/trace，禁止改架构。
- **TRACE**——找错误**第一次**出现的位置，按 CASE R / A–F 分类（`test` §2）。DB 层通常是对的，**泄漏首现于 B 或 D**。启用路由的系统先判 R：**Routing 错误是独立 first failure point**，downstream symptom 不改判分类。
- **DIAGNOSE**——结构化结论**先报告，后动手**。无 evidence = 无结论；confidence 低则回 TRACE。
- **PATCH**——**最小修改**。修复优先级：**Authorization / Scope Isolation > Request Routing > Retrieval Filter > Summary Isolation > Context Planner / Builder > Prompt > Reranking**——Routing 根因有明确位置，但不凌驾 Authorization / Scope Hard Guard。改一个 WHERE 条件优于改检索策略，改检索策略优于调重排权重，任何都优于重设计管线。**禁止借修 bug 顺手重构 Memory System。** 动手前先向用户说明：bug 在哪个文件哪个函数、为什么发生、改什么、影响面。
- **VERIFY**——核心回归 7 项（failing test 转 PASS / 场景 2 跨会话零泄漏 / 合法跨会话不误伤 / global memory 不误伤 / 场景 1 superseded 不回流 / 场景 7 不重复召回 / 场景 4 token 有界）+ 能力回归（按 `test` §7 能力→场景映射，**修改影响到的 capability，其对应测试必须全部通过**）。

## 症状定位索引

按症状直接跳到对应 reference 章节，不必通读：

| 症状 / 主题 | 去哪 |
|---|---|
| 该记的没记 / 记错了 / 冲突反复 | `arch` §3 Writer 门控与冲突消解 |
| 答的是别的会话的内容 / 跨会话泄漏 | `arch` §4 visible() + `test` §6 |
| Forget 后还在回答 / 幽灵记忆 | `arch` §5 tombstone 注入期屏蔽 |
| 摘要内容漂移 | `arch` §5 摘要管线（段不可变 / 深度 ≤ 1） |
| RAG / 工具结果被当成用户记忆 | `arch` §3 lineage 与 promotion_source_allowed |
| procedural 越权 / 用户要求"忽略系统规则" | `arch` §9.6 authority boundary |
| 意图识别错 / 工具选错 / 能力误激活 | `ru` §1–§5 |
| 路由建议被当成授权 | `ru` §0 + `arch` §0.9 |
| 上下文塞不下 | `arch` §5 压缩分级 + §9.5 Context Planner |
| 塞得下但模型找不到 / 决策质量持续劣化 | `arch` §6 Attention Budget（Context Rot） |
| 不知道该存哪一层 / 该用什么表示 | `arch` §1 七层 + §2 Representation Strategy |
| 要写测试 / 评估指标 | `test` |
