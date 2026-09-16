# 记忆/上下文架构详细模式

生产验证过的完整设计。定位：**Pattern Library / 设计参考**，不是必须照抄的固定架构——BUILD Workflow 按产品需求选择需要的层与机制，不默认全部启用；偏离本文模式必须说明理由。原则：**用现有字段组合表达分层，不为架构图好看建新表**。

模式分组：**Core（§0–§8）** 所有启用长期记忆的项目默认适用（§1 Structured Core vs Raw History 是 Core Design Question、§2 Representation Strategy、§6 Context Stability 为设计决策维度，答案可为 required/optional/not_needed；§4 Raw History Retrieval 是按项目启用的 capability）；**Taxonomy（§9.1）** memory_type 正交分类模型（semantic/episodic/procedural），不属于“默认关闭的 Advanced Pattern”；**Advanced（§9.2–§9.9）** 默认关闭，BUILD 逐项输出 required / recommended / optional / not_needed + reason——唯一例外 §9.6：procedural memory 启用时自动强制（mandatory guardrail），不参与选配；**Optional（§10）** 特定领域才考虑；**Sources（§11）** 仅来源说明。禁止把 Advanced/Optional 当默认开启。

## Runtime Information Architecture（统一运行时管线）

本文与 request-understanding.md（请求理解与路由模式库）、testing.md（测试矩阵）共同构成 Agent Runtime Information Architecture 设计参考：Request Understanding 决定请求怎么被理解与调度，Memory（§1–§5、§9）决定跨 session 记什么/怎么读写，Context（§6、§9.4–§9.5）决定每个决策点让模型看到什么。运行时最高原则：

```text
Understand → Route → Retrieve → Plan Context → Act → Update → Evaluate
```

完整管线（Request Understanding 是统一入口；Memory / Context 机制即本文 §2–§9）：

```text
User Request
     ↓
Trusted Metadata / Session State（user_id / thread_id / project_id / active task）
     ↓
Request Understanding（request model：intent × scope × temporal × information needs × capability plan）
     ↓
Hard Scope / Authorization Guard（Routing suggests. Authorization decides. Visibility enforces.）
     ↓
Capability Plan 执行（capability_plan=false 的节点物理跳过，§6 能力门控）
     ↓
┌─────────────┬─────────────┬─────────────┬─────────────┐
│   Memory    │  Knowledge  │    Tools    │ External SoT│
│ (§2–§5/§9)  │    (RAG)    │             │  (实时查询)  │
└─────────────┴─────────────┴─────────────┴─────────────┘
     ↓
Context Planner（§9.5）→ Context Assembly（§6，三段布局）
     ↓
LLM
     ↓
Response / Action
     ↓
State / Memory Update（§3 Writer Gate / §5 Forget / Task State）
     ↓
Evaluate（testing.md）
```

关键约束：Request Understanding 只产出 request model 与 capability **建议**——Memory 可见性仍由 §4 visible() 硬过滤决定，工具权限仍由 system policy / tool permission / ACL / user authorization 决定（§0.9–0.10）；"记住 X" 类请求只产生 memory_write_candidate，仍过 §3 Writer 全部门控；routing 输出属 Dynamic Runtime State，不污染 §6 Stable Prefix。请求理解与路由的模式库（Request Model / 路由分级 / taxonomy 推断 / ambiguity fail-closed / 收编表）见 request-understanding.md——现有会话范围路由、双路由、能力门控由其统一供给触发判定，实现不变。

## 0. Hard Invariant 与 Recommended Default

**Hard Invariant**（与参数无关；启用对应基础能力后必须满足，测试必须覆盖——测试分层见 testing.md：Universal Hard Invariant / Capability Hard Tests / Quality Metrics）：

1. thread 隔离：scope=thread 的记忆只在本 thread 可见；跨会话内容只能经显式历史路由进入。
2. 证据优先级：explicit > inferred_strong > inferred_weak，推断永不覆盖明确陈述。
3. superseded/forgotten 默认不可召回：status='active' 且 valid_to 未过期（valid_to IS NULL = 未过期，即永久有效）双条件过滤；唯显式历史路由可读 superseded（见 §4）。
4. scope/有效性硬过滤在语义排序之前；scope 错误不得用相似度阈值、reranker 或 prompt 补救。
5. 敏感信息写入门控一票否决；LLM 判定失败默认不写。
6. SummarySegment 不可变；摘要深度 ≤ 1，禁止摘要套摘要。
7. 可变状态不写长期记忆；**untrusted external context（工具结果/检索片段/RAG 内容）永不直接成为持久 memory**——对 interactive 与 derived 两类 candidate source 都成立（§3）。约束的是外部内容不得直接持久化，不是"每条候选必须直接来自对话消息"。
8. 被 Forget 的事实不得回流最终 prompt——记忆/摘要/digest/缓存任何路径都不行；靠 tombstone 注入期屏蔽（见 §5），不靠"以记忆段为准"的仲裁声明。
9. **Router 只选择候选、不授予权限**：routing 结果（capability_plan.tools=true、scope_intent=project 等）不构成 tool authorization、不扩大 Memory visibility——权限由 system policy / tool permission / application ACL / user authorization / guardrail 决定，可见性仍由 §4 visible() 硬过滤执行（Routing suggests. Authorization decides. Visibility enforces.，模式见 request-understanding.md §0）。
10. **Intent 歧义 fail closed**：scope/temporal 无法确定时默认解析到 current / 更窄 scope，绝不用扩大信息可见范围来消除歧义（与第 4 条 scope 硬过滤、project fail closed 同族）；仅 material ambiguity（显著影响权限/scope/副作用/工具操作/结果正确性）才向用户澄清。

**Recommended Default**（本文全部数字皆属此类：经验起点，应通过真实数据集与 eval 校准，不是架构真理）：

```text
writer_confidence_min = 0.5     # inferred_weak 单独要求 ≥ 0.8
dedup_cosine_distance = 0.15   # cosine distance < 0.15 = similarity > 0.85，视为同一事实
recent_window = 16             # 进 prompt 的最近原文消息条数
summary_segment_size = 8       # 每个不可变段覆盖的消息条数
summary_budget = 800 字         # 会话摘要上限（触发一次深度 1 合并）
memory_item_budget = 200 字     # 单条记忆注入截断
memory_top_k = 8                # 单次注入记忆条数上限
memory_total_budget = 1600 字   # 记忆段注入总预算（≈ top_k × item_budget，防"百条×200字"撑爆）
rag_budget = 20000 字           # RAG 段总预算
tool_result_budget = 4000 字    # 工具结果段预算（request-scoped）
rerank_weights = 语义 0.40 / 字面 0.15 / importance 0.15 / confidence 0.10
              / 强化 0.10 / 频次 0.05 / recency 0.05
```

## 1. 七层记忆映射表

|  | 层 | 存哪里 | 生命周期 | 隔离键 | 关键约束 |
| --- | --- | --- | --- | --- | --- |
| Working Context | 图/请求 State | 单次请求 | — | 只放本步需要的；不放聊天全史 |  |
| Session Memory | 最近窗口原文 + 会话摘要行 | 一个会话 | thread\_id | 窗口内原文进 prompt；窗口外的进摘要，原文留库不重复摘要 |  |
| Task Memory | 结构化运行态（goal/status/todo/unresolved），挂在会话行 | 一个任务 | task 所属 thread | 完成后必须停止注入；**不是 memory 表记录，不占 scope 枚举** |  |
| Project Memory | 长期记忆表的 project scope | 长期 | project\_id | 产品没有 project 概念前不建（YAGNI） |  |
| User Memory | 长期记忆表 global scope | 长期 | user\_id | 只存跨任务仍有价值的偏好/事实/约束 |  |
| Knowledge Memory | 文档库 + RAG | 长期 | doc/owner | 与用户记忆分开检索、分开预算 |  |
| External Context | 工具/API 实时取 | 单次请求 | — | 永不当长期记忆存；可变资产同此 |  |

### Structured Core Memory + Raw History Archive（Core Design Question）

七层回答存取与隔离；长期信息系统还有一条正交设计问题——**结构化核心 vs 原始历史**。这是 **Core Design Question**：所有 BUILD 必答三问——是否保留 raw source？是否需要 searchable raw history？是否需要 Overview → Detail？——但答案可以是 required / optional / not_needed，**不是所有启用长期记忆的项目都必须有 Searchable Raw History**：

- **Structured Core Memory**：少量、高价值、稳定、跨任务有用、已压缩/结构化的信息——用户偏好、长期约束、项目关键决策、稳定工作方式、重要实体关系。即 §2 memory 表承载的主体（semantic / episodic / procedural cards；决策等领域经 `domain` 字段表达，如 `domain='decision'`）。对启用长期记忆的项目通常 required。
- **Raw History Archive**：原始 messages、trajectory、tool interaction history（按 retention policy，tool 归档语义见 §6 双生命周期）、event history。职能——按需 historical retrieval / evidence recovery / provenance / detail lookup，**不是每轮进 context**。其检索能力（§4 Raw History Retrieval）是**按项目启用的 capability**。

选型参考：简单 preference chatbot = Structured Core required / Searchable Raw History not_needed（YAGNI——**不为长期记忆自动创建 raw-history vector index**）；Coding / Research Agent = Structured Core required / Raw History Retrieval recommended 或 required。

保留语义（与 §4 retention 前提一致）：

```text
normal operation:              append-only（不为了摘要、Memory 更新而重写历史）
retention expiry:              delete / archive according to policy
hard delete / privacy erasure: erase according to policy
```

append-only 指**不为摘要/Memory 更新而重写**，不表示不可因 retention / privacy / hard-delete 而删除。

```text
              Long-term Information
                     │
          ┌──────────┴──────────┐
          │                     │
   Structured Core        Raw History Archive
          │                     │
 semantic / episodic       raw messages
 procedural cards          trajectory
 (+ domain e.g. decision)  source evidence
          │                     │
          └──────────┬──────────┘
                     │
               Context Planner
                     │
             current request
```

Source of Truth 关系：Structured Memory 是压缩模型/索引/抽象；Raw History 是历史证据。要来源、原话、事件细节、历史证明时优先回 Raw History；但 raw old history **不自动覆盖 current active semantic memory**——“现在住哪”走 active memory，“以前住哪”才回 raw/history（Normal/Historical Route，§4）。**Core = navigation/overview，Raw = detail/evidence**（检索管线见 §4「Raw History Retrieval」）。

## 2. Memory 表 schema（该有的和不该加的）

必备字段：`user_id, scope(global/thread/project), scope_id, memory_type, domain, content(单句独立可读), raw_content(触发原文), embedding, importance, confidence, source_type(explicit/inferred_strong/inferred_weak), status(active/superseded/forgotten), valid_from, valid_to, superseded_by, reinforcement_count, last_confirmed_at, access_count, created/updated_at`。

scope 说明：`scope_id` 在 scope=thread 时存 thread\_id、scope=project 时存 project\_id、scope=global 时为空。Task 运行态不进本表（见表 1）。`valid_to` = NULL 表示无过期时间——永久有效，直到被 supersede/forget；不用 magic future date。`status='forgotten'` 行即 Forget tombstone（见 §5）：行保留、永不注入，content/embedding 仅供抑制匹配。

**不要加的字段**（实战结论）：

- `key/value` 拆分——单句 content 已够，结构化拆分对一句话记忆是过度设计
- `memory_versions` 独立表——`superseded_by` 链 + `status` 已构成隐式版本史
- `memory_relations` / 知识图谱——PostgreSQL + JSONB + pgvector 够用时是复杂度负担
- `tenant_id`——单租户部署就是永久的 NULL 列
- `evidence_type` 独立字段——`source_type` 已表达

结构化补充放 `structured_data` JSONB：`{reason, entities, alternatives, decision_status}`。**memory_type 值域只有 semantic / episodic / procedural**，decision 不占用 memory_type 值——决策用现有 `domain='decision'` + structured_data 表达：「项目决定使用 PostgreSQL」= `memory_type='semantic', domain='decision'`；历史决策事件（“9 月评审否掉了 MongoDB 方案”）= `memory_type='episodic', domain='decision'`。复用现有表，不建 decisions 表，不为此新增 schema 列。溯源（provenance）同样不加列：调试需要时在 JSONB 记 `{source_conversation_id, source_message_id, source_turn, writer_version}` 即可（`source_message_id` 指向原始消息主键：消息合并/编辑后 source_turn 会漂移，message id 稳定），`raw_content` 本身就是最强证据。

### Memory Representation Strategy（设计决策维度，不是 DB 字段）

scope/lifecycle × memory_type 之外，BUILD 为每类信息选择第三个设计维度——**表示方式**。它默认不是数据库新列（content + structured_data 已够承载），是 per-信息类型的设计决策，落在 information_mapping 与 memory_trace：

- **atomic_note**：单一事实、简单 preference、简单 constraint（“用户喜欢深色主题”）。
- **enhanced_note**：一个事实需要少量上下文才能独立理解（“用户主要用 Python 做数据分析，更偏好 pandas 而不是纯 SQL”）。
- **structured_card**：多个相关字段、稳定实体、需要局部更新的信息（如 work_profile：role/company/team/stack，放 structured_data）。局部更新与 §3 SUPERSEDE 统一：**logical update = field-level patch，persistence = new full card snapshot → supersede 旧卡**——例：旧卡 `{company: A, role: Designer, stack: Figma}`，用户只说“我现在是 Senior Designer 了”，逻辑 patch 只改 role，但持久化为携带全量字段的新卡、旧卡 status=superseded。provenance / version chain（superseded_by）/ historical route / conflict resolution 全部复用现有机制，不建 card_versions 表。有独立 Source of Truth 的实体应进结构化业务状态/store，不做长期 Memory card。
- **rich_contextual_card**：复杂事件、人物关系、背景原因、重要项目决策——可携带 entity / relationship / backstory / timestamp / provenance。
- **raw_history_reference**：不值得完全结构化、但未来要能恢复细节的原始会话/trajectory——**不是新的长期事实 memory**，是指向 raw conversation archive 的引用（message range / source ids），配合 §1 Raw History Archive 使用。

**Representation 不机械绑定 memory_type**：Semantic+atomic_note、Semantic+structured_card、Episodic+enhanced_note、Episodic+rich_contextual_card、Procedural+atomic_note 都合法。表示由信息复杂度、更新频率、关系复杂度、检索方式、token cost 共同决定——简单事实被过度结构化、复杂实体被压成模糊单句，都是 Representation 反模式。

## 3. 写入门控完整流程

```
交互结束 → 候选提取（路由层预判 memory_write_candidate，寒暄/纯知识问答不进门）
        → 终判 LLM（结构化输出：should_store/type/domain/scope/lifetime/valid_to/source_type/importance/confidence；永久事实 valid_to 输出 NULL，不写 magic future date）
        → 硬门控：confidence ≥ 0.5；inferred_weak ≥ 0.8；敏感信息正则（API key/身份证/手机号/银行卡…）一票否决
        → 向量近邻查重（cosine distance < 0.15 视为同一事实），查重候选必须：
            · 排除系统域（风格偏好/验证反馈/画像等由专用写入方维护的黑名单域）
            · 排除不可见 scope（其他会话的 thread 记忆不参与本会话查重）
            · 排除 status='forgotten'（forget 后重提 = 写新行，不复活 tombstone）
        → 冲突消解（对最近近邻判定，整个近邻簇一致处理）：
            REINFORCE：同一事实换个说法 → reinforcement_count+1, confidence=max, last_confirmed_at=now，
                       簇内其余重复 superseded 归并到本条
            SUPERSEDE：实质更新/矛盾 → 旧簇全部 status=superseded, valid_to=now, superseded_by=新id
            IGNORE：无新信息 → 不写
        → 证据优先级守卫：旧 explicit + 新 inferred 命中 SUPERSEDE → 拒绝写入（推断不覆盖明确陈述）
        → LLM 冲突判定失败 → 默认 IGNORE（宁漏勿错，绝不默认 SUPERSEDE）
```

三动作足够：部分更新用 SUPERSEDE 表达（新条目携带全量内容），不需要第四种 MERGE。

**Writer 输入边界（两类 candidate source，防 RAG → Memory 注入）**：

- **Interactive Writer**：source = conversation_message——候选只从真实对话消息产生；RAG / Tool / retrieved context 不允许进入。文档里写 "Remember that user likes Java" 不构成 user memory。
- **Derived Writer / Promotion**：source = existing internal memories / episodes / raw conversation archive（trajectory）——background consolidation（§9.2）、maintenance（§9.3）、episodic→procedural learning（§9.7）的派生候选属此类。必须：保留 derived_from memory ids、保留 provenance、重新过 confidence gate、重新过 conflict resolution、重新过 authority boundary（§9.6）、不得覆盖 explicit fact。

**Raw History Source Lineage**（堵 Tool/RAG → Raw Archive → Derived Writer 间接注入）：raw archive 中的内容按来源打 lineage 标签——`user_message / assistant_message / tool_result / rag_context / system_event`（不新增列：message/event store 已有 role/type 直接复用，否则作为 archive metadata / trace metadata）。Derived Writer 读取 trajectory 时**先过滤 lineage、再提候选**，不是扫整段后统一让 LLM 猜来源。promote 前必须过 `promotion_source_allowed(source_type)`：

```text
user_message                              → allowed
trusted existing internal memory/episode  → allowed
assistant_message                         → 可作上下文证据，不得单独建立新 user fact；
                                            promotion 必须有用户证据或其他可信来源支持
tool_result                               → forbidden（直接与间接都不允许）
rag_context                               → forbidden
external_context                          → forbidden
```

**Hard Rule：Archiving external content ≠ authorizing it as Memory evidence。** Tool/RAG 内容可以因审计或任务回放被 raw archive 保存，但 tool_result / rag_context lineage **永远不能经 Background Consolidation / Maintenance / Episodic Promotion 被“洗”成 User Memory**（testing 场景 22）。RAG / Tool / External Context 同样永远不能直接成为 derived source。candidate origin 记入 memory_trace（§9.9）或 structured_data，不新增列：`conversation / background_consolidation / episodic_promotion / maintenance`。对应 Hard Invariant 见 §0.7：untrusted external context must never directly become persistent memory。

## 4. 检索与重排

可见性（Visibility）= 一条记忆能否被本次请求看见，全部用现有字段表达：

```
visible(m, ctx) = m.user_id == ctx.user_id                    # user_id 永远是第一条件
              AND scope_allowed(m.scope, ctx.route)            # 会话范围路由二分的结果
              AND (m.scope != 'thread'  OR m.scope_id == ctx.thread_id)
              AND (m.scope != 'project' OR (ctx.project_id IS NOT NULL
                                            AND m.scope_id == ctx.project_id))
              AND m.status == 'active'                         # superseded/forgotten 均不可见
              AND (m.valid_to IS NULL OR ctx.now < m.valid_to) # NULL = 永久有效
```

project 隔离 fail closed：`scope_allowed` 只在请求携带显式 project 上下文（ctx.project_id 非空）时把 'project' 放进允许集。普通 user 路由看不到任何 project 记忆——同一 User 的 Project A 记忆对 Project B 请求零可见，无 project 上下文的请求对全部 project 记忆零可见。不确定时收窄可见范围，绝不扩大。

双路由（Normal / Historical）：

- **normal route**（默认，一切普通问题）：只用上式，superseded 永不召回。
- **historical route**（仅显式历史意图，如"以前/之前/曾经住哪"）：放开 status 与 valid_to 两条（SUPERSEDE 时 valid_to=now，对历史行它只是版本时间戳），允许 status='superseded' 并沿 superseded_by 链回溯；user/scope/project 隔离一条不放松，status='forgotten' 仍不可见（forget ≠ 历史）。触发判定与元问题路由同机制：LLM 判定 + 本地关键词兜底，普通问题一律走 normal route。

双路由的触发判定统一来自 Request Understanding 的 `temporal_intent`（request-understanding.md §8.1 收编表）——判定实现（LLM + 关键词兜底）与本节可见性/隔离规则不变，Routing 只是统一入口。

episodic 恢复带 **retention 前提**：只要 episode 未被 forget、未被 hard-delete / privacy erasure、仍在产品 retention policy 内，historical route 必须能从 active / cold / archive tier 恢复——进入 cold/archive tier 只影响普通召回显著性（salience decay），不剥夺 historical 恢复能力。forget / deletion / retention policy 优先于 historical recoverability。

```
Visibility 硬过滤（上式，先于一切语义排序）
→ 多查询召回（原 query + 任务条件扩展：食物问题扩展"过敏/忌口"，代码任务扩展"技术栈偏好"）
→ 关键词/实体字面召回（补向量漏召回）
→ 加权重排：0.40*语义 + 0.15*字面命中 + 0.15*importance + 0.10*confidence
           + 0.10*强化次数 + 0.05*使用频次 + 0.05*recency
→ 可选 LLM Reasoner 过滤无关 + 冲突只留最新 → top_k 截断（记忆段总预算见 §0）
```

权重理由：语义主导但非独裁；乘法公式在任一信号为 0 时把记忆打没，**用加权和不用乘积**；recency 压到最低——"用户偏好 Python"三年前写的今天依然成立。

元问题（"我问过什么"类）分两类，都不走向量检索，数据源必须跟着会话范围路由走：

- "这个会话/刚才问了什么" → 只用当前 thread 的消息与会话摘要；
- "以前/其他聊天聊过什么" → 用户级 digest（会话标题列表 + 资产清单）+ TTL 缓存。

digest 是 user 级快照：把它注入“这个会话”类问题，就是最典型的 B 类泄漏。

### Raw History Retrieval（Overview → Detail）

本节是**按项目启用的 capability**（§1 选型：判定 not_needed 的项目不建 raw-history 检索索引）。Core Memory 是 navigation/overview，Raw History 是 detail/evidence。任务需要 Core 未保存的具体细节时，正确行为不是继续猜，而是触发 raw-history retrieval：

```text
Structured Overview（core memory 命中导航线索）
→ detect missing detail → raw/history retrieval（scope 过滤 + 相关性过滤 + 预算）
→ retrieve evidence/detail → answer
```

例：Core 已知“用户去年参与 Project X”，问“当时具体是怎么解决数据库问题的？”→ 检索 raw history 找回对应原始证据作答，不凭 overview 编细节。与双路由的语义关系：普通问题仍走 active memory（normal route）；显式历史意图 / detail lookup 走 historical route 与本节 raw retrieval，user/thread/project 隔离一条不放松。

**索引期增强（contextual prefix）**：raw conversation 块在索引前可先生成一段简短上下文前缀（时间/人物/意图，如“[用户在本块中修改了此前设立的转账指令]”）再嵌入——孤立块（“好的，就订这个吧”）脱离上下文无信息量，前缀把块锚回语义环境，同时改善稠密与字面两路召回；复用现有 embedding 管线，索引期一次性成本，不新增基础设施。

**Hard Rule——Raw History 不得重新变成“全部聊天塞进 prompt”**：必须 `search/retrieve → scope filter → relevance filter → budget → inject selected evidence`；禁止 `load all conversations → dump into context`。Raw History Retrieval 同样遵守 user isolation、thread/project scope、retention policy、Forget/privacy semantics——tombstone 注入期屏蔽（§5）对 raw 检索结果同样生效（见 testing 场景 21）。

## 5. 摘要管线（防事实漂移）

- 滑动窗口保留最近 N 条原文（默认 16）：窗口内原文进 prompt 的会话段；窗口外消息才进摘要。原始消息在产品 retention / privacy / deletion policy 允许范围内保留（审计/回放用）——append-only 指不为摘要 / Memory 更新而重写（见 §1 保留语义），不表示不可因 retention/privacy/hard-delete 而删除；窗口外的不重复进模型上下文。
- 窗口外消息按固定段长（默认 8 条/段）封存为**不可变 SummarySegment**：每段从原文生成一次，永不重写、永不再摘要。
- 会话摘要 = 各段拼接；超过预算（默认 800 字）才做一次 LLM 合并（深度 1）。**禁止摘要套摘要**。
- 结构化运行态（active\_task/waiting\_for\_user/pending\_todo）与会话摘要同表不同字段，由路由层顺带更新（0 额外 LLM）。
- Forget/删除记忆不回写摘要（段不可变），抑制在注入期完成（见下「Forget 抑制」）。
- **Compression Principle**：压缩的目标不只是让 context 塞得下，还包括提高 information density。优先压缩 old trajectory、large tool results、重复历史、低价值 context；避免频繁重写 stable system prefix、tool definitions、trusted stable rules（见 §6 Context Stability）。SummarySegment 不可变、深度 ≤ 1 规则不变。
- **Summary ≠ Memory**：Summary 是当前 thread 历史的压缩表示；Memory 是跨时间有长期价值的信息模型。引入压缩不改变这条边界——Background Writer 仍必须独立判断“是否值得长期保存”（§3 门控），不得把 Summary 自动当 User Memory 落库。

### Forget 抑制（tombstone，Ghost Summary 防护）

只写"记忆段与会话摘要冲突时以记忆段为准"防不了 Ghost Summary：Memory 段的**缺席**无法告诉模型"该事实已被明确禁止"，旧 Summary/Digest/缓存里的原话仍会回流。Forget 的完整语义是"该事实不得作为当前有效用户事实进入任何 prompt"。用现有表表达（零新表、零新列）：

1. **识别**：路由层识别 forget 请求，向量/字面定位目标 active 记忆（限定本 user + 当前可见 scope）。
2. **tombstone 化**：命中行转 `status='forgotten'`，不物理删除；content 与 embedding 保留，仅供第 4 步匹配。
3. **同步失效**：从 **normal retrieval 向量索引**移除该条；DB 行内 embedding 保留、仅供 suppression 匹配——tombstone 永不回到普通检索索引。vector store 做不到"库留行、索引删"时，suppression 改用 content fingerprint / 关键词实体匹配等独立表示，同样不得回插检索索引。该 user 的检索缓存与 digest TTL 缓存一并失效。
4. **注入期屏蔽（遵守 scope）**：Context Builder 在注入会话摘要/digest/缓存上下文前，用**本请求可见的** tombstone 对每段做匹配（cosine distance < 0.15，复用查重阈值，或字面包含），命中句子剥离，剥离不净则整段丢弃。摘要保持不可变。tombstone 可见性用独立的 suppression_visible，与 visible() 共享 user/scope 判定形状但**不是一个函数**——正常召回看 status='active'，抑制看 status='forgotten'，且不看 valid_to：

    suppression_visible(t, ctx) = t.user_id == ctx.user_id
                              AND scope_allowed(t.scope, ctx.route)
                              AND (t.scope != 'thread'  OR t.scope_id == ctx.thread_id)
                              AND (t.scope != 'project' OR (ctx.project_id IS NOT NULL
                                                            AND t.scope_id == ctx.project_id))
                              AND t.status == 'forgotten'

   global tombstone 对该 user 的所有允许上下文生效；thread tombstone 只屏蔽本 thread；project tombstone 要求 ctx.project_id 非空且匹配，无 project 上下文不可见（fail closed）。Project A 的 tombstone 不得误杀 Project B 的合法同形事实。
5. **防复活**：查重候选排除 forgotten（§3）——forget 后用户重提该事实 = 写新行，tombstone 不动。

**tombstone ≠ Memory Fact**：tombstone 永不进入任何 prompt 段，不会把"用户喜欢辣"重新告诉模型；它只告诉系统——旧摘要里的这句话不得作为当前用户事实使用。tombstone 通常个位数，注入期匹配开销可忽略。

## 6. 上下文组装与预算

```
system(固定) + [风格偏好] + [长期记忆(每条截断，top_k/总预算封顶)] + [digest(仅显式历史路由)] + [会话摘要]
+ [最近窗口原文] + <context>RAG</context> + <tool_result>工具结果</tool_result> + query
```

| 段 | source | scope | 默认预算 | 丢弃顺序 |
|---|---|---|---|---|
| system | 静态 | — | 固定 | 不丢 |
| 风格偏好 | 专用写入方的系统域 | user | 小 | 最后丢 |
| 长期记忆 | memory 表 | global / 当前 thread / 当前 project | 每条 200 字，总 1600 字（top_k=8） | 重要性低者先丢 |
| digest | 会话标题列表 + 资产清单 | user，**仅显式历史路由才注入** | 小 | 不走该路由 = 物理不注入 |
| 会话摘要 | SummarySegment 拼接 | 当前 thread | 800 字 | 保头尾段 |
| 最近窗口原文 | 消息表 | 当前 thread | 16 条 | 保最近 |
| RAG | 文档库 | doc/owner | 20000 字 | 头尾块优先保，中间先截 |
| 工具结果 | 工具/API 当次返回 | 当前请求（request-scoped） | 4000 字 | 已被后续结果取代的先丢 |

- 能力门控：Request Understanding 输出的 capability_plan 为 false 的模块**物理跳过节点**，不要"检索了再让模型忽略"。needs_memory / needs_knowledge / needs_tools 是 capability_plan 的最小键集（完整键集与 realtime_state/external_state 术语见 request-understanding.md §7）；external_state=false 时实时 Source of Truth 查询节点同样物理跳过，external_state=true 只注入本请求真正需要的实时结果——Dynamic Tail，不进 Stable Prefix、不自动进 User Memory。
- **Tool Result 双生命周期语义**：**Runtime Tool Result**（默认）= request-scoped——只用于当前 context 与当前任务计算，请求结束后不得作为 active context 延续、不得成为 User Memory、不得自动参与后续请求（即 §1 External Context 行），也不是 Memory Writer 候选输入（§3 输入边界）。**Optional Tool Audit / Event Archive**：产品确有 audit / replay / provenance / debugging / historical task inspection 需求时，允许按 retention policy 把 tool call / tool result / tool metadata 保存进 Raw History / Event Archive——但必须带 `lineage=tool_result`，且 archive ≠ memory：`promotion_source_allowed(tool_result) = false`（§3），归档永不使其获得 Memory Evidence 权限。无 audit/history 需求的项目 archive = not_needed（YAGNI）。
- 资产类可变数据注入时必须带仲裁声明："以本实时数据为准；若与长期记忆不一致，视为已删除/变更"。记忆段与会话摘要冲突时同理：以记忆段为准——但 forget 场景不能只靠这句仲裁，必须叠加 §5 的 tombstone 注入期屏蔽。
- 上表字符预算是 **implementation fallback**（简单项目直接用）；启用 Context Planner 的项目升级为 token 预算动态分配（见 §9.5）。

### Context Stability 与 Cache-Friendly Layout（布局维度）

段表回答“放哪些内容、多少预算、丢弃顺序”；Context Stability 是正交的**布局/排序维度**——不仅考虑 relevance/token，还考虑 context block 的稳定性与缓存复用：

| 稳定性分段 | 典型内容 | 设计原则 |
|---|---|---|
| **Stable Prefix** | system/safety policy、稳定 agent instructions、稳定 tool definitions、长期不变的 trusted project instructions | 内容与顺序尽量稳定；不无理由插入时间戳/随机值/实时状态；避免每轮重写 |
| **Semi-stable / Retrieved** | selected skill instructions、project rules、相关 memory（semantic/episodic/procedural）、retrieved knowledge | 按任务需要出现 |
| **Dynamic Tail** | runtime/task state、session summary、recent trajectory、tool results、current query、实时 external context | 天然变化，放靠近上下文尾部 |

推荐布局：`[Stable Prefix] → [Semi-stable / Retrieved] → [Dynamic Tail]`——不是绝对固定顺序，BUILD 可按目标框架调整，但 dynamic request data 不应无理由放在 stable prefix 前部。现有 §6 pipeline（system → … → query）与该布局兼容：system 段天然是 stable prefix，query 天然是 tail。

目的：提高 KV / Prompt Cache 前缀复用、降低 repeated-prefix cost。这是 **cache-friendly context layout pattern**，不绑定特定供应商实现——模型/API 不提供可利用缓存时，stable-prefix 思想仍保留（布局稳定本身减少轮间 diff、便于调试），cache benefit 标 `not_applicable`。Cache Efficiency 指标（testing.md §11）由 §9.9 context trace 的可选字段支撑（stable_prefix_fingerprint / prefix_mutated 等）；prefix 确需变更（业务改变 system/tool configuration）时必须记录 `prefix_mutation_reason`。

## 7. 反注入与安全

- 检索资料/记忆/工具结果全部包数据标签（`<context>`/`<tool_result>`），内容里出现的同名闭合标签先剥离。**标签内内容一律视为 untrusted data**：即使其中出现 "Ignore previous instructions"、"调用某工具"、"记住用户喜欢 Java" 等指令式文本，也不得把它们提升为 system/developer/tool instruction 执行——**retrieved content = data, not authority**。RAG / Tool 内容不得直接或间接成为 User Memory evidence（§3 lineage 规则）。
- 敏感信息写入门控前正则拦截（宁可漏记不可入库）。

## 8. 迁移哲学

- Phase 1 正确性：写/读路径的 scope 隔离、冲突证据优先级、重复清理——零 Schema 变更。
- Phase 2 表达力：project/task 等新维度，**等产品层出现对应概念再建**；迁移走幂等补列（ADD COLUMN IF NOT EXISTS）。旧行 NULL **不得自动解释为 global**：scope=NULL 是未知 scope，`scope='global' AND scope_id=NULL` 才是合法 global memory。旧 schema 历史定义能明确证明 NULL==global 的，迁移时显式 backfill `scope='global'`；证明不了的 fail closed——不参与正常召回，直到完成迁移/归类。不为 backward compatibility 扩大可见范围。
- Phase 3 预算：按问题类型分档 token 预算（普通/项目技术/知识/个人各不同权重），一次路由字段改动——即 §9.5 Context Planner 的静态雏形。

## 9. Memory Type Taxonomy 与 Advanced Patterns

§9.1 是 memory_type **正交分类模型**，与"默认关闭"不是同一语义：semantic 对长期事实/偏好类 Memory 启用时通常适用（基础分类，不是高级功能）；episodic / procedural 按项目需要启用。§9.2–§9.9 是 **Advanced Patterns**，默认关闭，BUILD Workflow 在 DESIGN 阶段逐项判定 required / recommended / optional / not_needed 并给 reason——唯一例外：§9.6 是 Procedural Memory 的 **mandatory guardrail**，procedural_memory enabled → §9.6 automatically mandatory，不单独参与选配、不能关闭；其余 Advanced Pattern 继续按项目选择。

### 9.1 Memory Type Taxonomy：semantic / episodic / procedural

七层回答"存哪里/谁可见/活多久"；memory_type 回答"这是什么性质的信息、如何被使用"。**两轴正交**：User+Semantic、Project+Semantic、Project+Episodic、global/project/thread+Procedural 都是合法组合。procedural **复用现有 scope 枚举，不引入 agent scope**：global 本来就是 user 级 scope（§1 User Memory 行）——global procedural = 针对当前 user、跨 thread/project 适用的行为偏好或工作习惯（"给我代码前先解释""回答尽量简洁"），**不是 system-wide / agent-wide rule**；project procedural = 项目专属规则；thread procedural = 极少使用、仅会话内临时策略。真正的 system-wide / agent-wide policy **不得存入 user memory 表**，应来自 trusted system policy / agent configuration；未来 Multi-Agent 确需 agent-specific ownership 时，经 §10.3 migration 以 owner_type/owner_id 引入。复用 §2 现有 `memory_type` 字段，值域 = semantic / episodic / procedural（decision 等领域分类走 `domain` 字段，见 §2）：

- **semantic**：稳定事实/偏好/约束/属性（"用户喜欢深色主题""项目用 PostgreSQL"）——现有 memory 表主体，无增量成本。
- **episodic**：过去的任务/尝试/结果/成败经验（"上次部署失败是 migration 未锁表"）。`structured_data` 记 `{outcome, task_type, entities}`。**historical validity ≠ retrieval salience**：episodic 不因新事实 supersede——旧 episode 是真实历史，只能 forget，不会"过期"；但旧 episode 可以降低检索优先级、进入 cold/archive tier、经 salience decay 降低普通召回，且满足 retention 前提（未 forget、未 hard-delete / privacy erasure、仍在产品 retention policy 内）时，explicit historical route 必须能从 active/cold/archive tier 恢复（见 §4）。不因"旧"改写或删除历史事实；recency ≠ truth。
- **procedural**：Agent 行动规则/策略/技能（"migration 前必须检查 lock strategy"）。检索时作为 instruction 注入，受 §9.6 authority boundary（mandatory guardrail，随 procedural 启用自动生效）约束；默认不修改 system prompt（见 9.6）。

选型参考：普通聊天 Agent = semantic required / episodic optional / procedural not_needed；Coding/长任务 Agent = semantic+episodic required / procedural recommended。

### 9.2 Hot Path + Background Consolidation（双路径形成）

- **Hot Path**（默认）：用户明确"记住/改成/搬到"类陈述 → 立即走 §3 现有管线，无新机制。
- **Background Consolidation**（可选，默认关）：多轮行为模式 / 重复反馈 / 相似 episode 簇 / 记忆碎片，由异步批任务处理：

  ```text
  raw interactions → pattern candidate → evidence count → confidence
  → conflict check → promotion（Derived Writer：origin=background_consolidation，
  重新过 §3 全部门控）
  ```

  硬约束：① background 推断永不覆盖 explicit（铁律 6 的延伸，产出按 inferred_strong 起步）；② 不进用户当前响应 critical path；③ 项目不需要可整体禁用；④ 产出是 derived candidate（§3 Derived Writer）——source 只能是现有内部 memories/episodes/raw conversation archive，保留 derived_from 与 provenance。例：过去 15 次用户都要求“先解释再给完整代码” → background 产出 candidate preference，过门控后才落库。

  完整职责（与 §9.3 hygiene 协同）：candidate extraction / dedup / generalization / representation selection（§2 Representation Strategy）/ card update / episode clustering / promotion / hygiene / provenance preservation。后台 Memory Processing 思想统一并入本节与 §9.3，**不新建第二套 Memory Processor 模块**；Hot Path + Background 双路径结构保持。

### 9.3 Memory Maintenance / Hygiene（长期运行）

写入时 dedup/conflict/supersede/forget（§3/§5）解决不了长期碎片化。触发条件（Recommended Default）：memory_count 超阈值 / duplicate_density 或 contradiction_density 过高 / 长期未访问 / episodic 大量积累 / 同一模式反复 reinforcement。可执行操作：

```text
merge duplicates / cluster similar episodes / supersede stale
promote repeated episode → semantic / promote repeated strategy → procedural
cleanup low-value
```

硬约束：**不改写 explicit user fact**（只能 supersede/forget，不许顺手润色）；一切 promotion/consolidation 走 §3 Derived Writer（origin=maintenance），在 `structured_data` 保留 provenance：`{derived_from: [memory_ids], consolidated_at, policy_version}`。维护是批任务，不在请求路径上。

### 9.4 Progressive Disclosure（三层上下文）

- **Tier 1 Core/Pinned**：当前任务、安全规则、项目硬约束、用户明确的重要限制。极小；**最高保留优先级，不参与普通 relevance-based dropping，但受模型硬 context window 限制**。硬溢出处理链：system/safety/mandatory instructions → pinned structured compaction（结构化压缩，不删约束）→ second-stage retrieval / deferred context → 仍放不下则 fail closed 显式报错——**不得静默截断关键约束**。
- **Tier 2 Retrieved**：按 query 召回的相关 user/project memory、episodic、RAG——即 §6 Context Builder 主体。
- **Tier 3 Discoverable**：不注入内容，只注入目录（namespace / index / category / file path / metadata），Agent 发现缺上下文时主动 search/open/retrieve：

  ```text
  Available memory namespaces:
    project-decisions/  past-incidents/  user-preferences/  successful-solutions/
  ```

选型：短聊天 bot = not needed；coding/research/长任务 = recommended；超大项目 = required。§6 现有设计 = Tier 1+2，Tier 3 纯增量。skill / capability instructions 同样适用 Progressive Disclosure——模型先知道有哪些能力/namespace 可用，真正需要时再加载具体 Skill/instructions/files，不一开始把全部 Skill 正文塞进 context；归入本 Pattern，不新增第四层。

### 9.5 Context Planner 与 Token 预算

现有 §6 静态字符预算保留为 fallback；启用 Planner 后升级为请求级动态分配：

```text
available_input_tokens = model_context_window - system_tokens - output_reserve - mandatory_context
```

实现允许 character approximation，不强制 tokenizer 精确。**Context Planner** 输入：model_context_window / output_reserve / query_type / task_complexity / current_task / available_memory_types / needs_history / needs_rag / needs_tools / retrieval_confidence——其中 query_type / task_complexity / needs_* 统一来自 Request Understanding 的 request_model（intent / scope / temporal / information_needs / capability_plan，request-understanding.md §8.3），Planner 消费而不重新判定。输出 context_plan：

```yaml
context_plan:
  pinned:               {budget_tokens: ...}
  recent_messages:      {budget_tokens: ...}
  session_summary:      {enabled: ..., budget_tokens: ...}
  semantic_memory:      {enabled: ..., budget_tokens: ..., top_k: ...}
  episodic_memory:      {enabled: ..., budget_tokens: ..., top_k: ...}
  procedural_memory:    {enabled: ..., budget_tokens: ...}
  rag:                  {enabled: ..., budget_tokens: ...}
  external_state:       {enabled: ..., budget_tokens: ...}   # 实时 SoT 查询结果（Dynamic Tail）
  tool_results:         {enabled: ..., budget_tokens: ...}
  discoverable_context: {enabled: ...}   # Tier 3 目录
```

**Query/task-aware 策略**：intent 决定 memory type 权重与块预算（intent/scope/temporal 均来自 request_model）——寒暄 → 关 retrieval；“我喜欢什么” → semantic 高优；“上次这个 bug 怎么解决的” → episodic 高优；“这个项目代码怎么写” → project+procedural+RAG；“我以前住哪里” → historical semantic。与 §4 的 scope 维度路由（会话范围/双路由）互补，不替代。retrieval_confidence 低或缺上下文时允许第二轮 retrieval（经 Tier 3 主动补拉）。

**双目标升级（High Signal + Bounded Tokens + Stable Prefix）**：Planner 在 relevance/token 之外增加 stability/cache friendliness 目标——段分配尊重 §6 三段布局，stable prefix 不因单次请求重排。context_strategy 属于 Context Architecture Decision，不强制新增 runtime schema：

```yaml
context_strategy:
  stable_prefix:
    blocks: []          # system/safety、trusted instructions、stable tool defs
    mutation_policy: "内容与顺序稳定；变更需显式理由（时间戳/随机值/实时状态不进 prefix）"
  semi_stable:
    blocks: []          # selected skills、project rules、memory、knowledge
  dynamic_tail:
    blocks: []          # task state、summary、trajectory、tool results、query
  cache_strategy:
    enabled: false
    reason: "provider 无可利用 prefix cache，cache benefit = not_applicable；stable-prefix 布局仍保留"
```

provider 支持 prompt/prefix cache 时 `cache_strategy.enabled: true` 并记录缓存边界；不支持时 stable-prefix 思想仍保留（布局稳定本身减少轮间 diff、便于调试），cache benefit 标 `not_applicable`。

### 9.6 Procedural Memory 安全边界与 Authority Boundary（mandatory guardrail）

本节**不是可选 Advanced Pattern**：只要 procedural memory 启用即自动强制（procedural_memory enabled → §9.6 automatically mandatory），不单独参与 required/recommended/optional/not_needed 选择，不能关闭。

procedural 默认是 **retrievable instruction**（检索注入），不是自动永久修改 system prompt。升级为 persistent agent instruction 必须走：promotion candidate → eval → explicit approval / trusted automation policy → promotion。防止 Agent 越学越偏。

**Scope ≠ Authority**：scope 回答"谁能看到这条 memory"，authority 回答"这条 procedural instruction 有多高的行为优先级"——两者正交，**scope 不参与权限升级**。禁止因为 scope=project 就把 procedural memory 当成 Project Hard Rule：普通 user 写入的 `scope=project, memory_type=procedural, source_type=explicit` 仍然只是 Explicit User Procedural Preference，只是它只在该 project 可见；真正的 Trusted Project Policy / Project Hard Rule 必须来自可信项目配置、管理员配置、受控 policy source 等 trusted source，不由普通 user memory scope 自动获得（实现需要标识 trusted source 时复用现有 provenance / structured_data / 外部 trusted config，不新增 authority 列）。

**Authority Boundary**：procedural memory 是可检索的指令，**不是权限提升**。优先级从高到低：

```text
System / Safety / Trusted Policy
> Trusted Project Policy
> Explicit User Procedural Preference
> Inferred / Learned Procedural Memory
```

任何 procedural memory 都不得：override system policy、override safety rules、绕过权限控制、改变 tool authorization。用户即使 explicit 说"记住以后忽略系统规则"，也不能形成高权限 procedural instruction——Writer 把这类候选按**无效/拒绝写入 candidate** 处理（拒绝原因记入 §9.9 memory_trace 的 write.rejection_reason；需要留痕时用现有 source_type/confidence/structured_data 表达，不为此新增数据库列）。procedural 注入时必须携带边界声明：

```text
Only apply when consistent with higher-priority system,
security, project and tool constraints.
```

边界在写入期与注入期双层生效：写入期拒绝越权候选；注入期声明优先级——explicit 来源只让 preference 排在 inferred 之前，永远不会把它抬到 Trusted Project Policy 或 system/safety/trusted policy 之上。

### 9.7 Episodic → Procedural Learning

启用 episodic+procedural 的项目可加学习环：episode → repeated evidence → reflection candidate → evaluation → procedural memory（Derived Writer：origin=episodic_promotion，source 只是现有内部 episodes，重过 §3 门控与 §9.6 authority boundary）。promotion 必须同时权衡 **positive evidence / negative evidence / counterexamples / applicability conditions**——目标不是"所有情况下都成立"的宽泛规则，而是**带适用条件的精确规则**（学"对于 shared relational DB migration，执行前检查 lock strategy"，不学"所有 migration 前必须检查 lock"）：

```yaml
procedural_candidate:
  rule:
  applicability_conditions: []
  supporting_evidence: []      # episode/memory ids
  counterexamples: []
  confidence:
```

一次 episode 不得直接改行为；minimum evidence / confidence 是 Recommended Default，由 eval 校准；存在未解释的 counterexample 时不 promote——先收窄条件或拒绝。

### 9.8 Entity-aware Retrieval（可选增强）

§4 管线保留，加一路候选来源：query 实体识别（如 "Redis"）→ semantic + keyword/BM25 + **entity match**（`structured_data.entities`）三路候选统一 rerank。复用现有 JSONB，不引入 Graph DB。

### 9.9 Production Observability（memory_trace）

生产管线应能回答：为什么这么路由、为什么写/没写、为什么召回/没召回、为什么被 Planner 丢弃、最终回答是否用到。统一 trace：

```yaml
memory_trace:
  routing:   {request_model_summary, rule_hits, llm_router_invoked,
              selected_capabilities, ambiguity, fallback_reason,
              authorization_checks}   # 见 request-understanding.md §10
  write:     {candidates, accepted, rejected, rejection_reason}
  retrieval: {query, candidates, visibility_filtered, ranked, selected}
  context:   {planned_blocks, token_budget, dropped_items, drop_reason}
             # 可选 Context Stability 观测（§6；仅 debug/observability trace，不新增 DB 字段）：
             # stable_prefix_fingerprint / stable_prefix_tokens / prefix_mutated
             # / prefix_mutation_reason / cache_eligible_tokens
  usage:     {injected_memory_ids, explicitly_cited_memory_ids,
              attributed_memory_ids, attribution_confidence}
```

Context Stability 观测是 §6 Cache Efficiency 指标的数据源：provider 提供真实 cache hit 信息时**记录真实值**；不提供时 `cache_hit = unknown / not_applicable`，**不得推测**。

attribution 语义：`attributed_memory_ids / attribution_confidence` 是 **observability signal，不是 causal ground truth**——"Memory 是否真正提升结果"主要由 testing.md §10 的 End-task Delta Eval（No Memory vs Memory vs Oracle）判定。存储按 dev mode / sampling / debug mode 分级，不要求永久全量；routing 段不得永久记录 raw user text（除非产品 retention / privacy 明确允许，request-understanding.md §10）。

## 10. Optional Specialized Patterns（特定领域才考虑）

### 10.1 Graph Memory

仅当出现大量实体关系、多跳关系查询、关系随时间变化、复杂历史事实才考虑（Graph DB / Temporal KG）。**默认输出 `graph_memory: {status: not_needed, reason: "普通 User Memory 不需要图结构"}`**，不默认建议 Neo4j/Graphiti。

### 10.2 Bi-temporal Memory

仅当 CRM / finance / operations / 医疗·商业时间线类项目。区分"事实何时发生 vs Agent 何时知道"：`structured_data` 加 `{event_time, observed_at}`（例：用户 9/10 搬家、9/15 才告诉 Agent），不改基础 schema 列。

### 10.3 Multi-Agent / Shared Memory

仅当检测到 multiple agents / shared team state / organization knowledge / 协作。基础 scope 枚举（global/thread/project）**不动**；未来确需时以 owner_type / owner_id / namespace / ACL 作为 §8 式 migration pattern 引入，不预先抽象。

## 11. Design Sources / Inspirations

仅作来源说明，不构成运行时依赖——以下思想已全部工程化为本文自包含规则，Skill 运行不访问外部材料：

- 李博杰《深入理解 AI Agent：设计原理与工程实践》（开源主仓库 `bojieli/ai-agent-book`）：
  - **Chapter 1 Agent 基础**：Agent = LLM + Context + Tools；LLM 承担 understanding / reasoning / planning / decision → 对应 request-understanding.md 的定位：routing 是把 LLM 的理解转化为系统能力调度的桥，本身不是新的"智能层"。
  - **Chapter 2 上下文工程**：静态前缀 + 动态轨迹结构、“动态信息永远追加到末尾”、KV/Prompt Cache 友好布局（时间戳注入 system prompt 导致缓存失效的教训）、压缩双动机（长度约束 + 信息密度/思考质量）、压缩保留优先级、Agent Skills 渐进式披露（目录 → 按需加载）→ 对应本文 §5 Compression Principle、§6 Context Stability、§9.4、§9.5，以及 request-understanding.md §7（routing 只选 namespace 不注入内容）、§8.4（routing 输出不进 Stable Prefix）。
  - **Chapter 3 用户记忆和知识库**：四种存储格式（Simple Notes / Enhanced Notes / JSON Cards / Advanced JSON Cards）、三套正交分类（记忆层次 × 存储格式 × 认知类型）、轨迹 append-only（“轨迹是流水账，长期记忆是档案”）、双层记忆架构（结构化卡片常驻提供概览 + 检索按需提供细节）、对话历史本身即知识库、上下文感知检索（索引期前缀）、记忆压缩与整理（筛选/聚类/抽象泛化）→ 对应本文 §1 Structured Core + Raw History、§2 Representation Strategy、§4 Raw History Retrieval、§9.2/§9.3。
  - **Chapter 7 Agent 评估**：评估驱动校准（指标先行、阈值来自真实数据而非拍脑袋）→ 对应 request-understanding.md §6（routing_confidence 阈值经 eval 校准，自报分数不当真实概率）与 testing.md §8 Routing Quality。
- 主流 Agent 工程共识（不绑定框架，仅来源说明）：Anthropic《Building Effective Agents》《Effective Context Engineering for AI Agents》、OpenAI Agents SDK（handoffs / guardrails）、LangGraph（routing / structured output / conditional edges）——simplest sufficient router、structured output 路由、handoff vs agent-as-tool、guardrail 与路由分离 → 工程化为 request-understanding.md §2（Level 0–5）、§4（混合路由）、§9（Handoff vs Agent-as-Tool）、§0（Routing ≠ Authorization）。
- 本仓库生产系统实践（FastAPI + LangGraph + PostgreSQL/pgvector）——scope 隔离、Forget/tombstone、Writer 门控、procedural authority boundary、双路由、三层测试分类等 Core 机制来自线上真实故障与修复。
- Stable Prefix / Semi-stable / Dynamic Tail 三分段命名、`raw_history_reference` 表示、Cache Efficiency / Representation Fitness 评估指标、Request Understanding & Routing 的 Request Model / 路由分级 / 收编表为基于上述来源的**工程化扩展**，非原书原文。
