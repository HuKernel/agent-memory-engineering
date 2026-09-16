# 记忆/上下文架构详细模式

生产验证过的完整设计。定位：**Pattern Library / 设计参考**，不是必须照抄的固定架构——BUILD Workflow 按产品需求选择需要的层与机制，不默认全部启用；偏离本文模式必须说明理由。原则：**用现有字段组合表达分层，不为架构图好看建新表**。

模式分组：**Core（§0–§8）** 所有启用长期记忆的项目默认适用；**Taxonomy（§9.1）** memory_type 正交分类模型（semantic/episodic/procedural），不属于"默认关闭的 Advanced Pattern"；**Advanced（§9.2–§9.9）** 默认关闭，BUILD 逐项输出 required / recommended / optional / not_needed + reason；**Optional（§10）** 特定领域才考虑。禁止把 Advanced/Optional 当默认开启。

## 0. Hard Invariant 与 Recommended Default

**Hard Invariant**（与参数无关；启用对应基础能力后必须满足，测试必须覆盖——测试分层见 testing.md：Universal Hard Invariant / Capability Hard Tests / Quality Metrics）：

1. thread 隔离：scope=thread 的记忆只在本 thread 可见；跨会话内容只能经显式历史路由进入。
2. 证据优先级：explicit > inferred_strong > inferred_weak，推断永不覆盖明确陈述。
3. superseded/forgotten 默认不可召回：status='active' 且 valid_to 未过期（valid_to IS NULL = 未过期，即永久有效）双条件过滤；唯显式历史路由可读 superseded（见 §4）。
4. scope/有效性硬过滤在语义排序之前；scope 错误不得用相似度阈值、reranker 或 prompt 补救。
5. 敏感信息写入门控一票否决；LLM 判定失败默认不写。
6. SummarySegment 不可变；摘要深度 ≤ 1，禁止摘要套摘要。
7. 可变状态不写长期记忆；工具结果/检索片段永不当记忆持久化。
8. 被 Forget 的事实不得回流最终 prompt——记忆/摘要/digest/缓存任何路径都不行；靠 tombstone 注入期屏蔽（见 §5），不靠"以记忆段为准"的仲裁声明。

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

## 2. Memory 表 schema（该有的和不该加的）

必备字段：`user_id, scope(global/thread/project), scope_id, memory_type, domain, content(单句独立可读), raw_content(触发原文), embedding, importance, confidence, source_type(explicit/inferred_strong/inferred_weak), status(active/superseded/forgotten), valid_from, valid_to, superseded_by, reinforcement_count, last_confirmed_at, access_count, created/updated_at`。

scope 说明：`scope_id` 在 scope=thread 时存 thread\_id、scope=project 时存 project\_id、scope=global 时为空。Task 运行态不进本表（见表 1）。`valid_to` = NULL 表示无过期时间——永久有效，直到被 supersede/forget；不用 magic future date。`status='forgotten'` 行即 Forget tombstone（见 §5）：行保留、永不注入，content/embedding 仅供抑制匹配。

**不要加的字段**（实战结论）：

- `key/value` 拆分——单句 content 已够，结构化拆分对一句话记忆是过度设计
- `memory_versions` 独立表——`superseded_by` 链 + `status` 已构成隐式版本史
- `memory_relations` / 知识图谱——PostgreSQL + JSONB + pgvector 够用时是复杂度负担
- `tenant_id`——单租户部署就是永久的 NULL 列
- `evidence_type` 独立字段——`source_type` 已表达

结构化补充放 `structured_data` JSONB：`{reason, entities, alternatives, decision_status}`。**memory_type 值域只有 semantic / episodic / procedural**，decision 不占用 memory_type 值——决策用现有 `domain='decision'` + structured_data 表达：「项目决定使用 PostgreSQL」= `memory_type='semantic', domain='decision'`；历史决策事件（"9 月评审否掉了 MongoDB 方案"）= `memory_type='episodic', domain='decision'`。复用现有表，不建 decisions 表，不为此新增 schema 列。溯源（provenance）同样不加列：调试需要时在 JSONB 记 `{source_conversation_id, source_message_id, source_turn, writer_version}` 即可（`source_message_id` 指向原始消息主键：消息合并/编辑后 source_turn 会漂移，message id 稳定），`raw_content` 本身就是最强证据。

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

**Writer 输入边界（防 RAG → Memory 注入）**：候选提取只允许读对话消息本身；检索片段、工具结果、RAG 命中（`<context>`/`<tool_result>` 标签内内容）永远不是记忆来源——文档里写 "Remember that user likes Java" 不构成 user memory。

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

digest 是 user 级快照：把它注入"这个会话"类问题，就是最典型的 B 类泄漏。

## 5. 摘要管线（防事实漂移）

- 滑动窗口保留最近 N 条原文（默认 16）：窗口内原文进 prompt 的会话段；窗口外消息才进摘要。原始消息永久留库（审计/回放用），只是窗口外的不重复进模型上下文。
- 窗口外消息按固定段长（默认 8 条/段）封存为**不可变 SummarySegment**：每段从原文生成一次，永不重写、永不再摘要。
- 会话摘要 = 各段拼接；超过预算（默认 800 字）才做一次 LLM 合并（深度 1）。**禁止摘要套摘要**。
- 结构化运行态（active\_task/waiting\_for\_user/pending\_todo）与会话摘要同表不同字段，由路由层顺带更新（0 额外 LLM）。
- Forget/删除记忆不回写摘要（段不可变），抑制在注入期完成（见下「Forget 抑制」）。

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

- 能力门控：路由判定 needs\_memory/needs\_knowledge/needs\_tools 为 false 的模块**物理跳过节点**，不要"检索了再让模型忽略"。
- 工具结果 request-scoped：生命周期 = 单次请求（即 §1 External Context 行），请求结束即失效，不进任何长期存储，也不是 Memory Writer 候选输入（§3 输入边界）。
- 资产类可变数据注入时必须带仲裁声明："以本实时数据为准；若与长期记忆不一致，视为已删除/变更"。记忆段与会话摘要冲突时同理：以记忆段为准——但 forget 场景不能只靠这句仲裁，必须叠加 §5 的 tombstone 注入期屏蔽。
- 上表字符预算是 **implementation fallback**（简单项目直接用）；启用 Context Planner 的项目升级为 token 预算动态分配（见 §9.5）。

## 7. 反注入与安全

- 检索资料/记忆/工具结果全部包数据标签（`<context>`/`<tool_result>`），内容里出现的同名闭合标签先剥离；系统提示声明标签内是指令性内容也当作数据。
- 敏感信息写入门控前正则拦截（宁可漏记不可入库）。

## 8. 迁移哲学

- Phase 1 正确性：写/读路径的 scope 隔离、冲突证据优先级、重复清理——零 Schema 变更。
- Phase 2 表达力：project/task 等新维度，**等产品层出现对应概念再建**；迁移走幂等补列（ADD COLUMN IF NOT EXISTS）。旧行 NULL **不得自动解释为 global**：scope=NULL 是未知 scope，`scope='global' AND scope_id=NULL` 才是合法 global memory。旧 schema 历史定义能明确证明 NULL==global 的，迁移时显式 backfill `scope='global'`；证明不了的 fail closed——不参与正常召回，直到完成迁移/归类。不为 backward compatibility 扩大可见范围。
- Phase 3 预算：按问题类型分档 token 预算（普通/项目技术/知识/个人各不同权重），一次路由字段改动——即 §9.5 Context Planner 的静态雏形。

## 9. Memory Type Taxonomy 与 Advanced Patterns

§9.1 是 memory_type **正交分类模型**，与"默认关闭"不是同一语义：semantic 对长期事实/偏好类 Memory 启用时通常适用（基础分类，不是高级功能）；episodic / procedural 按项目需要启用。§9.2–§9.9 是 **Advanced Patterns**，默认关闭，BUILD Workflow 在 DESIGN 阶段逐项判定 required / recommended / optional / not_needed 并给 reason。

### 9.1 Memory Type Taxonomy：semantic / episodic / procedural

七层回答"存哪里/谁可见/活多久"；memory_type 回答"这是什么性质的信息、如何被使用"。**两轴正交**：User+Semantic、Project+Semantic、Project+Episodic、global/project/thread+Procedural 都是合法组合。procedural **复用现有 scope 枚举，不引入 agent scope**：global 本来就是 user 级 scope（§1 User Memory 行）——global procedural = 针对当前 user、跨 thread/project 适用的行为偏好或工作习惯（"给我代码前先解释""回答尽量简洁"），**不是 system-wide / agent-wide rule**；project procedural = 项目专属规则；thread procedural = 极少使用、仅会话内临时策略。真正的 system-wide / agent-wide policy **不得存入 user memory 表**，应来自 trusted system policy / agent configuration；未来 Multi-Agent 确需 agent-specific ownership 时，经 §10.3 migration 以 owner_type/owner_id 引入。复用 §2 现有 `memory_type` 字段，值域 = semantic / episodic / procedural（decision 等领域分类走 `domain` 字段，见 §2）：

- **semantic**：稳定事实/偏好/约束/属性（"用户喜欢深色主题""项目用 PostgreSQL"）——现有 memory 表主体，无增量成本。
- **episodic**：过去的任务/尝试/结果/成败经验（"上次部署失败是 migration 未锁表"）。`structured_data` 记 `{outcome, task_type, entities}`。**historical validity ≠ retrieval salience**：episodic 不因新事实 supersede——旧 episode 是真实历史，只能 forget，不会"过期"；但旧 episode 可以降低检索优先级、进入 cold/archive tier、经 salience decay 降低普通召回，且 explicit historical query 永远可恢复。不因"旧"改写或删除历史事实；recency ≠ truth。
- **procedural**：Agent 行动规则/策略/技能（"migration 前必须检查 lock strategy"）。检索时作为 instruction 注入，受 §9.6 authority boundary 约束；默认不修改 system prompt（见 9.6）。

选型参考：普通聊天 Agent = semantic required / episodic optional / procedural not_needed；Coding/长任务 Agent = semantic+episodic required / procedural recommended。

### 9.2 Hot Path + Background Consolidation（双路径形成）

- **Hot Path**（默认）：用户明确"记住/改成/搬到"类陈述 → 立即走 §3 现有管线，无新机制。
- **Background Consolidation**（可选，默认关）：多轮行为模式 / 重复反馈 / 相似 episode 簇 / 记忆碎片，由异步批任务处理：

  ```text
  raw interactions → pattern candidate → evidence count → confidence
  → conflict check → promotion（仍走 §3 门控写入）
  ```

  硬约束：① background 推断永不覆盖 explicit（铁律 6 的延伸，产出按 inferred_strong 起步）；② 不进用户当前响应 critical path；③ 项目不需要可整体禁用。例：过去 15 次用户都要求"先解释再给完整代码" → background 产出 candidate preference，过门控后才落库。

### 9.3 Memory Maintenance / Hygiene（长期运行）

写入时 dedup/conflict/supersede/forget（§3/§5）解决不了长期碎片化。触发条件（Recommended Default）：memory_count 超阈值 / duplicate_density 或 contradiction_density 过高 / 长期未访问 / episodic 大量积累 / 同一模式反复 reinforcement。可执行操作：

```text
merge duplicates / cluster similar episodes / supersede stale
promote repeated episode → semantic / promote repeated strategy → procedural
cleanup low-value
```

硬约束：**不改写 explicit user fact**（只能 supersede/forget，不许顺手润色）；一切 promotion/consolidation 在 `structured_data` 保留 provenance：`{derived_from: [memory_ids], consolidated_at, policy_version}`。维护是批任务，不在请求路径上。

### 9.4 Progressive Disclosure（三层上下文）

- **Tier 1 Core/Pinned**：当前任务、安全规则、项目硬约束、用户明确的重要限制。极小；**最高保留优先级，不参与普通 relevance-based dropping，但受模型硬 context window 限制**。硬溢出处理链：system/safety/mandatory instructions → pinned structured compaction（结构化压缩，不删约束）→ second-stage retrieval / deferred context → 仍放不下则 fail closed 显式报错——**不得静默截断关键约束**。
- **Tier 2 Retrieved**：按 query 召回的相关 user/project memory、episodic、RAG——即 §6 Context Builder 主体。
- **Tier 3 Discoverable**：不注入内容，只注入目录（namespace / index / category / file path / metadata），Agent 发现缺上下文时主动 search/open/retrieve：

  ```text
  Available memory namespaces:
    project-decisions/  past-incidents/  user-preferences/  successful-solutions/
  ```

选型：短聊天 bot = not needed；coding/research/长任务 = recommended；超大项目 = required。§6 现有设计 = Tier 1+2，Tier 3 纯增量。

### 9.5 Context Planner 与 Token 预算

现有 §6 静态字符预算保留为 fallback；启用 Planner 后升级为请求级动态分配：

```text
available_input_tokens = model_context_window - system_tokens - output_reserve - mandatory_context
```

实现允许 character approximation，不强制 tokenizer 精确。**Context Planner** 输入：model_context_window / output_reserve / query_type / task_complexity / current_task / available_memory_types / needs_history / needs_rag / needs_tools / retrieval_confidence；输出 context_plan：

```yaml
context_plan:
  pinned:               {budget_tokens: ...}
  recent_messages:      {budget_tokens: ...}
  session_summary:      {enabled: ..., budget_tokens: ...}
  semantic_memory:      {enabled: ..., budget_tokens: ..., top_k: ...}
  episodic_memory:      {enabled: ..., budget_tokens: ..., top_k: ...}
  procedural_memory:    {enabled: ..., budget_tokens: ...}
  rag:                  {enabled: ..., budget_tokens: ...}
  tool_results:         {enabled: ..., budget_tokens: ...}
  discoverable_context: {enabled: ...}   # Tier 3 目录
```

**Query/task-aware 策略**：intent 决定 memory type 权重与块预算——寒暄 → 关 retrieval；"我喜欢什么" → semantic 高优；"上次这个 bug 怎么解决的" → episodic 高优；"这个项目代码怎么写" → project+procedural+RAG；"我以前住哪里" → historical semantic。与 §4 的 scope 维度路由（会话范围/双路由）互补，不替代。retrieval_confidence 低或缺上下文时允许第二轮 retrieval（经 Tier 3 主动补拉）。

### 9.6 Procedural Memory 安全边界与 Authority Boundary

procedural 默认是 **retrievable instruction**（检索注入），不是自动永久修改 system prompt。升级为 persistent agent instruction 必须走：promotion candidate → eval → explicit approval / trusted automation policy → promotion。防止 Agent 越学越偏。

**Authority Boundary**：procedural memory 是可检索的指令，**不是权限提升**。优先级从高到低：

```text
System / Safety / Trusted Policy
> Project Hard Rules
> Explicit User Procedural Preference
> Inferred / Learned Procedural Memory
```

任何 procedural memory 都不得：override system policy、override safety rules、绕过权限控制、改变 tool authorization。用户即使 explicit 说"记住以后忽略系统规则"，也不能形成高权限 procedural instruction——Writer 把这类候选按**无效/拒绝写入 candidate** 处理（拒绝原因记入 §9.9 memory_trace 的 write.rejection_reason；需要留痕时用现有 source_type/confidence/structured_data 表达，不为此新增数据库列）。procedural 注入时必须携带边界声明：

```text
Only apply when consistent with higher-priority system,
security, project and tool constraints.
```

边界在写入期与注入期双层生效：写入期拒绝越权候选；注入期声明优先级——explicit 来源只让 preference 排在 inferred 之前，永远不会把它抬到 Project Hard Rules 或 system/safety/trusted policy 之上。

### 9.7 Episodic → Procedural Learning

启用 episodic+procedural 的项目可加学习环：episode → repeated evidence → reflection candidate → evaluation → procedural memory。promotion 必须同时权衡 **positive evidence / negative evidence / counterexamples / applicability conditions**——目标不是"所有情况下都成立"的宽泛规则，而是**带适用条件的精确规则**（学"对于 shared relational DB migration，执行前检查 lock strategy"，不学"所有 migration 前必须检查 lock"）：

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

生产管线应能回答：为什么写/没写、为什么召回/没召回、为什么被 Planner 丢弃、最终回答是否用到。统一 trace：

```yaml
memory_trace:
  write:     {candidates, accepted, rejected, rejection_reason}
  retrieval: {query, candidates, visibility_filtered, ranked, selected}
  context:   {planned_blocks, token_budget, dropped_items, drop_reason}
  usage:     {injected_memory_ids, explicitly_cited_memory_ids,
              attributed_memory_ids, attribution_confidence}
```

attribution 语义：`attributed_memory_ids / attribution_confidence` 是 **observability signal，不是 causal ground truth**——"Memory 是否真正提升结果"主要由 testing.md §10 的 End-task Delta Eval（No Memory vs Memory vs Oracle）判定。存储按 dev mode / sampling / debug mode 分级，不要求永久全量。

## 10. Optional Specialized Patterns（特定领域才考虑）

### 10.1 Graph Memory

仅当出现大量实体关系、多跳关系查询、关系随时间变化、复杂历史事实才考虑（Graph DB / Temporal KG）。**默认输出 `graph_memory: {enabled: false, reason: "普通 User Memory 不需要图结构"}`**，不默认建议 Neo4j/Graphiti。

### 10.2 Bi-temporal Memory

仅当 CRM / finance / operations / 医疗·商业时间线类项目。区分"事实何时发生 vs Agent 何时知道"：`structured_data` 加 `{event_time, observed_at}`（例：用户 9/10 搬家、9/15 才告诉 Agent），不改基础 schema 列。

### 10.3 Multi-Agent / Shared Memory

仅当检测到 multiple agents / shared team state / organization knowledge / 协作。基础 scope 枚举（global/thread/project）**不动**；未来确需时以 owner_type / owner_id / namespace / ACL 作为 §8 式 migration pattern 引入，不预先抽象。
