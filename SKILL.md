---
name: agent-memory-engineering
description: >
  Design, audit, and fix memory & context systems for LLM Agent applications,
  distilled from a production system (FastAPI + LangGraph + PostgreSQL/pgvector).
  Covers long-term memory, memory writer gating, conflict resolution, hybrid
  retrieval, session/conversation isolation, rolling summaries, and token budgeting.
  Use whenever the user mentions Agent memory, 记忆系统, 长期记忆, 上下文管理,
  context engineering, memory writer, 记忆检索, 记忆污染, 跨会话泄漏/串会话,
  conversation summary, session isolation, or wants to add / audit / refactor
  the memory or context layer of any AI agent project — even if they only
  describe a symptom like "agent 记错了" or "answers mention other conversations".
---

# Agent Memory / Context Engineering（实战方法论）

提炼自真实生产项目踩过的坑。核心信念：**记忆系统的 bug 几乎都是 scope/隔离问题，不是向量相似度问题**；上下文的 bug 几乎都是"错误内容在哪一步第一次进入流水线"的问题。

## 术语约定

全文 **thread == conversation == 会话**（同一概念；字段名以目标项目为准，下文统称 thread）。**scope** 是记忆的可见范围：`global`（用户级）/ `thread`（会话级）/ `project`（项目级）。**digest** 指会话标题列表 + 资产清单的轻量快照（user 级）。

## 按需求选路径

| 用户要什么 | 做法 |
|---|---|
| 从零设计记忆/上下文系统 | 读 `references/architecture.md`，按"七层映射 → 写入门控 → 检索 → 摘要 → 预算"顺序设计 |
| 现有系统有症状（串会话/记错/污染/答非所问） | 走下面的「调试工作流」定位 Root Cause，再查 `references/architecture.md` 对应模式 |
| 要写测试 / 验收 / 评估指标 | 读 `references/testing.md` |

## 铁律（冲突时按此序裁决）

1. 正确性 > 防记忆污染 > 上下文相关性 > 可维护性 > 性能 > Token 成本。
2. Memory ≠ 聊天记录；Context ≠ 全部历史。写库前必须过门控，进 prompt 前必须过预算。
3. **先复现、先 trace，再改代码**。Root Cause 未定位前禁止重构。
4. 会话/scope 隔离错误，禁止用"调 embedding 相似度阈值 / 换向量库"来修——那是把路由错误当检索问题治。
5. 没有 UI/API 消费方的 Schema 不要建（projects/tenant/memory_versions 表大多是 YAGNI；版本史用 `superseded_by` 链表达）。
6. 模型推断不得覆盖用户明确陈述（explicit > inferred_strong > inferred_weak）；写入门控 LLM 判定失败时默认不写，宁漏勿错。
7. 临时/可变状态（进度百分比、资产清单、本周在哪）不写入长期记忆——实时查询才是 Source of Truth。
8. 被 Forget 的事实不得回流最终 prompt：tombstone 在注入期屏蔽旧摘要/digest/缓存里的原话（`references/architecture.md` §5）；仅靠"以记忆段为准"的仲裁声明不够。

**参数哲学**：本文与 references 里的一切数字（阈值/权重/窗口/预算）都是 **Recommended Default**——经验起点，应通过真实数据集与 eval 校准，不是架构真理。Hard Invariant 是行为约束（见 `references/architecture.md` §0），与数字无关，不许放松。

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

### 6. VERIFY —— 七项回归全绿才算完

1. 原 bug 的 failing test 转 PASS；
2. 跨会话隔离：testing.md 场景 2（B 会话零泄漏）；
3. 合法跨会话不误伤：显式问"以前聊过什么"仍能召回；
4. 用户级 global memory 不误伤："我通常喜欢什么"仍工作；
5. superseded 记忆不回流：场景 1；
6. 重复记忆不重复召回：场景 7；
7. context token 有界：场景 4。

## 核心模式速查（详细版在 references/architecture.md）

**写入门控（Memory Writer）**：预判（路由层标记候选）+ 终判（结构化输出 should_store/type/scope/lifetime/source_type/confidence）→ 敏感信息正则拦截 → 向量近邻查重（限定同 scope + 排除系统域）→ 三动作冲突消解（REINFORCE 强化 / SUPERSEDE 失效挂链 / IGNORE），近邻重复簇整体处理而非只取第一条。候选只从对话消息提取——RAG/工具结果里的内容永远不构成记忆。

**检索（Hybrid）**：Visibility 硬过滤先行（user → thread/project scope 隔离，无 project 上下文 fail closed → status=active → valid_to 未过期、NULL=永久有效），向量 + 关键词混合召回，加权重排——语义主导，importance/confidence/字面命中做修正信号，**recency 权重刻意压低**（长期事实"越旧越不重要"是错的）。

**会话范围路由**：元问题必须二分——"这个会话/刚才/本次" → 只允许当前会话消息 + 当前会话摘要；"以前/其他聊天/历史" → 才允许用户级跨会话检索（digest）。加本地关键词短路兜底 LLM 判定摇摆。时间维度同理二分：普通问题只召回 active；显式历史意图（"以前/之前"）才走 historical route 读 superseded 链。

**摘要防漂移**：不可变分段（每段覆盖固定条数消息、从原文生成一次、永不再摘要），会话摘要 = 段拼接，超预算才做一次"深度 1"合并。摘要的摘要 = 事实漂移之源。最近窗口原文进 prompt，窗口外才进摘要。Forget 不重写摘要——tombstone 在注入期屏蔽。

**上下文组装**：分层预算 + 各段独立上限（最近窗口/摘要/记忆/RAG/工具结果），溢出截断保头尾关键块；能力门控（路由判定不需要的模块物理跳过，不是 prompt 里说"忽略"）。
