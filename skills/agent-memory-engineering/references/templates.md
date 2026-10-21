# 产出模板库

SKILL.md 的产出模板。宿主代理在**实际填写产出物时**才读本文件——SKILL.md 只保留工作流骨架与硬约束。

术语与文件缩写沿用 SKILL.md：`arch` = `references/architecture.md`，`ru` = `references/request-understanding.md`，`test` = `references/testing.md`。本文件内 `§` 号即对应文件。

---

## 1. Capability Scope Decision（BUILD 第一个动作）

```yaml
task_capabilities:            # 每项必带 reason
  request_understanding: {status: required | relevant | not_needed, reason: "..."}
  memory:                {status: required | relevant | not_needed, reason: "..."}
  context:               {status: required | relevant | not_needed, reason: "..."}
```

## 2. DESIGN 五类产出（合并填写，避免分头产出互相矛盾）

```yaml
selected_layers:              # 七层，arch §1
  working:   {status: required,    reason: "所有请求都需要 request-scoped state"}
  session:   {status: required,    reason: "窗口原文与会话摘要构成会话上下文主体"}
  task:      {status: required,    reason: "存在跨轮任务运行态"}
  project:   {status: not_needed,   reason: "产品不存在 project 概念，YAGNI"}
  user:      {status: required,    reason: "跨会话偏好/事实需要长期记忆"}
  knowledge: {status: optional,     reason: "有课程文档 RAG 时启用"}
  external:  {status: optional,     reason: "有实时可变数据时经工具当次注入"}
memory_types:                 # arch §9.1
  semantic:   {status: required,    reason: "用户偏好与约束"}
  episodic:   {status: recommended, reason: "跨会话复用排障经验"}
  procedural: {status: not_needed,  reason: "个人聊天 Agent，无稳定行动规则"}
representation_strategy:      # arch §2
  atomic_note:         {status: required, reason: "用户偏好/简单约束为主"}
  enhanced_note:       {status: optional, reason: "部分事实需少量上下文才独立理解"}
  structured_card:     {status: optional, reason: "存在稳定实体档案需局部更新"}
  rich_contextual_card:{status: not_needed,  reason: "当前无复杂关系/决策类信息"}
  raw_history_reference:{status: not_needed, reason: "无跨会话细节回溯需求"}
advanced_patterns:            # arch §9.2–§9.9
  background_consolidation: {status: recommended, reason: "多轮行为模式需沉淀且不进 critical path"}
  progressive_disclosure:   {status: not_needed,  reason: "上下文体量小，Tier 3 目录无增益"}
  context_planner:          {status: optional,    reason: "查询类型分档差异大时启用 token 动态预算"}
  entity_retrieval:         {status: optional,    reason: "查询常含实体名，三路召回有增益"}
  graph_memory:             {status: not_needed,  reason: "无多跳关系查询，图库是纯负担"}
  bitemporal_memory:        {status: not_needed,  reason: "非 CRM/finance/时间线类项目"}
  shared_memory:            {status: not_needed,  reason: "单 Agent，无协作共享态"}
routing_strategy:             # ru §2 分级 + §1 schema + §3 taxonomy
  level: 3
  reason: "自然语言 scope + 组合意图，确定性规则覆盖不足"
  request_model:
    fields:  [primary_intent, scope_intent, temporal_intent, capability_plan, ambiguity]
    dropped: [risk, secondary_intents]     # 无工具无副作用 → 删，写理由
  intent_taxonomy: {mode: hybrid, intents: [...], unknown_fallback: other}
  handoff_policy: not_needed               # Level 5 才填（ru §9）
```

status 词表：layer = required / optional / not_needed；memory_type、representation、advanced pattern = required / recommended / optional / not_needed。**每项必带 reason**；arch §9.6（procedural authority boundary）随 procedural 启用自动强制，不参与选配。

## 3. Information Mapping（MODEL 阶段）

```yaml
information_mapping:
  - information: user preference
    scope: global          # global / thread / project
    memory_type: semantic  # semantic / episodic / procedural
    representation: atomic_note
```

## 4. architecture_decisions（DESIGN 关键取舍）

```yaml
architecture_decisions:
  - pattern: graph_memory
    decision: not_needed
    reason: "只需要用户偏好与简单项目事实，无多跳关系查询"
    alternatives_considered: ["pgvector + entities JSONB"]
    why_not: "无关系遍历需求，图库是纯负担"
```

覆盖**全部 not_needed 的高级模式**与**偏离模式库之处**。`pattern` 字段的取值来自：七层（arch §1）/ memory_type（arch §9.1）/ 五种 representation（arch §2）/ advanced patterns（arch §9.2–§9.9 + §10）/ `raw_history_retrieval`（arch §1 Core Design Question 的三问之一）/ `context_planner`（arch §9.5）。

## 5. memory_system_blueprint（无代码项目的 Implementation-ready 输出）

```yaml
memory_system_blueprint:
  product_model:               # DISCOVER 的 product_context 结论
  selected_layers:             # DESIGN 结论
  memory_types:                # DESIGN 结论
  representation_strategy:     # DESIGN 结论
  advanced_patterns:           # DESIGN 结论
  information_mapping:         # MODEL 结论
  write_policy:                # what_to_store / what_not_to_store / explicit_vs_inferred
                               # / dedup / conflict_resolution / forget / background_consolidation
  retrieval_policy:            # visibility / normal_route / historical_route
                               # / hybrid_retrieval / reranking / entity_retrieval
  context_policy:              # blocks / priority / budgets / drop_policy
                               # / progressive_disclosure / context_planner
  context_stability:           # stable_prefix / semi_stable / dynamic_tail / cache_strategy
  request_routing_policy:      # routing level + reason / request_model 裁剪
                               # / intent_taxonomy + unknown 兜底 / capability_plan 键集
                               # / ambiguity fail-closed / routing_trace（不永久记录 raw user text）
  long_term_information:       # structured_core / raw_history_archive / retrieval
                               # 的 required/optional/not_needed 判定
  compression_strategy:        # 压缩优先序 + SummarySegment 约束（不需要的写 not_needed + reason）
  summary_policy:
  storage_design:              # 表 schema / 向量库 / 缓存 key 设计
  implementation_components:   # Pattern → 现有组件清单
  evaluation:                  # required_tests / metrics
```

## 6. evaluation_plan（EVALUATE）

```yaml
evaluation_plan:
  required_tests: []          # 能力 → 场景映射（test §7）筛出的必测场景
  optional_tests: []
  skipped_tests:
    - test: 场景 9
      reason: "无 RAG，仅保留工具结果断言"
  quality_metrics: []         # 选用的 test §8–§11 指标 + 项目校准阈值
```

## 7. DIAGNOSE 结构化结论（调试工作流）

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

## 8. AUDIT 差距报告

```yaml
gaps:
  - severity:                 # blocker / major / minor
    violated_invariant:       # arch §0 的第 N 条，或铁律 N
    location:                 # file:function 或 schema 位置
    fix_hint:
test_matrix:                 # 选定场景 + 跳过的场景 + reason
priority:                    # 按 PATCH 优先序排
```

## 9. AGENT_MEMORY_DESIGN.md 骨架

```markdown
# Agent Memory Design

## Capability Scope Decision
## Selected Layers          # status + reason
## Memory Types             # status + reason
## Representation Strategy  # status + reason
## Advanced Patterns        # status + reason
## Routing Strategy         # level + reason
## Architecture Decisions    # not_needed 理由 + 备选
## Information Mapping
## Change Log               # 每次修订追加
```
