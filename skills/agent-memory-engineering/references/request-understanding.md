# 请求理解与路由（Request Understanding & Routing）模式

提炼自真实生产系统与主流 Agent 工程共识（见 architecture.md §11）。定位：**Pattern Library / 设计参考**，与 architecture.md 平级——architecture.md 管 Memory / Context 的存取与组装，本文管请求进入后的**理解与调度**。**不是平行系统**：现有会话范围路由、Normal/Historical 双路由、能力门控、Writer 预判、forget 识别全部**收编**为 Request Understanding 的实现（§8.1 收编表：入口统一、实现不变）。术语按 SKILL.md 约定。

运行时最高原则（完整管线图见 architecture.md 开篇「Runtime Information Architecture」）：

```text
Understand → Route → Retrieve → Plan Context → Act → Update → Evaluate
```

## 0. 定位与硬边界

Request Understanding 不是 intent classifier。`query → intent: refund` 对现代 Agent 不够——它是**多维理解结构**，回答：

```text
用户想做什么？           primary / secondary intent
涉及什么 scope？         thread / project / user / external
涉及什么时间范围？       current / historical / future / timeless
需要什么信息？           semantic / episodic / procedural / raw history / knowledge / realtime
需要调用哪些能力？       capability_plan
是否执行动作、有无副作用？ action_need / risk
是否需要澄清？           ambiguity（仅 material 时）
```

Router 的能与不能（违反即触犯 architecture §0.9–0.10 Hard Invariant）：

```text
能：  判定 intent / scope_intent / temporal_intent
     产出 capability_plan（建议）
     标记 memory_write_candidate / forget candidate
     选择 route（normal / historical / thread / digest / external SoT）

不能：直接返回 Memory        —— 一切 Memory 访问过 architecture §4 visible() 硬过滤
     跳过或扩大 Visibility   —— scope 不确定时收窄（fail closed）
     直接写 Memory           —— 一切写入过 architecture §3 Writer 全部门控
     授予任何权限            —— capability_plan.tools=true ≠ tool authorization；
                               scope_intent=project ≠ project visibility
```

**Routing suggests. Authorization decides. Visibility enforces.** 权限最终由 system policy / tool permission / application ACL / user authorization / guardrail 决定；Memory 可见性由 user_id / thread_id / project_id / scope policy 硬过滤——router 的判定不改变其中任何一条。

## 1. Request Model（多维请求模型）

Recommended Schema——**BUILD 按项目裁剪，禁止为架构漂亮让所有项目使用全部字段**：

```yaml
request_understanding:
  primary_intent:
    type:                      # 来自项目 intent taxonomy（§3），不是通用分类
    confidence:
  secondary_intents: []        # 多意图；不强行单选
  scope_intent:
    level: thread | project | user | external | unknown
    target_id:                 # project_id 等；unknown = 待定（fail closed，§5）
  temporal_intent:
    type: current | historical | future | timeless | unknown
  information_needs:           # 检索侧重提示，不等于最终召回结果
    [semantic_memory, episodic_memory, procedural_memory,
     raw_history, knowledge, realtime_state]
  action_need:
    type: answer | retrieve | tool_action | mutate_state | delegate
  capability_plan:             # §7；最重要的输出
    session_history: false
    user_memory: false
    project_memory: false
    raw_history: false
    rag: false
    tools: false
    specialist_agent: false
  ambiguity:
    detected: false
    material: false            # true 才澄清（§5）
  risk:
    side_effect: none | low | high
    authorization_required: false
  routing_confidence:          # §6；自报分数，非校准概率
```

维度**正交**：intent × scope × temporal × information needs × action 各自独立判定、组合表达——不要造包含几百个组合 label 的巨型 taxonomy。多意图示例：

```text
"上次这个项目数据库为什么出问题，最后怎么解决的？"
→ primary_intent:    troubleshoot
  scope_intent:      {level: project, target_id: 当前 project}
  temporal_intent:   historical
  information_needs: [episodic_memory, raw_history]
  capability_plan:   {project_memory: true, raw_history: true, tools: false}
```

术语对齐：请求侧 `scope_intent.level=user` 即存储侧记忆 scope 的 `global`（用户级）——一个从请求视角命名、一个从存储视角命名，同一语义，勿混。裁剪规则：**字段必须有消费方**（capability_plan / Context Planner / routing_trace），无消费方的字段不建（SKILL.md 铁律 5 的同型约束）——单 Agent 无历史查询 → scope/temporal 可退化为 needs_history 一个布尔；无工具无副作用 → 删 risk / action_need。

## 2. Routing Strategy 分级（Level 0–5）

原则：**simplest sufficient router**——从 Level 0 往上找第一个够用的，不从 Level 3 起步再减配。

| Level | 机制 | 适用 | 升级触发 |
|---|---|---|---|
| 0 无专职路由 | good tool descriptions + good instructions + 模型原生 tool selection，零额外 LLM call | 单 Agent、工具少、模型可直接可靠选择工具 | 误路由率可观测上升 |
| 1 确定性路由 | rules / regex / request metadata / UI state / API route | "刚才/这个会话"→thread；"忘掉…"→forget；显式 project_id→project；realtime 请求→external SoT | 自然语言 scope / 组合意图出现 |
| 2 结构化 LLM 路由 | LLM structured output（schema validated） | 语义 intent、复杂表达、组合意图、自然语言 scope | 确定性信号覆盖不足且语义复杂 |
| 3 混合路由 | 硬规则 / metadata → LLM 理解 → validation → capability routing | **生产推荐默认** | route 数量大（数十以上） |
| 4 分层路由 | Domain → Capability → Specialist 两级路由 | route 数量大 | — |
| 5 Agent / Specialist 路由 | handoff / agent-as-tool（§9） | 不同任务真的需要不同 prompts / tools / permissions / context / expertise | — |

规则：

- Level 2+ **必须 Structured Output + schema validation**；禁止 LLM 输出一句自然语言再 regex parse。
- Level 3 = **Deterministic where possible, LLM where semantic reasoning is needed**；现有「LLM 判定 + 本地关键词短路兜底」即其实例（§8.1）。
- Level 4 仅 route 数量大时启用——十个 route 不建 router tree。
- Level 5 禁止把 intent label 机械映射成独立 Agent（§9）。
- 分级是 BUILD 的**选型输出**（routing_strategy.level + reason），不是运行时动态切换。

## 3. Intent Taxonomy 来自产品

禁止内置 refund / complaint / purchase / support 之类通用 taxonomy。BUILD 在 DISCOVER 阶段从 **PRD / API / Tools / 现有 routes / user journeys / business actions / agent capabilities** 推断 Intent Space：

```yaml
intent_taxonomy:
  mode: closed | open | hybrid   # 有限业务动作 / 开放域 / 核心闭合 + other 兜底
  intents:
    - name:
      definition:                # 一句话边界
      examples: []               # positive
      boundary: []               # near-boundary 样本
      counterexamples: []        # hard negatives
      route_target:              # capability 组合 / 数据源 / specialist（不是"一个 Agent"）
```

- **unknown / other / unsupported 必须存在**——否则所有请求都被强行塞进已有分类。
- 每个重要 route 三类样本都要给，目的是**降低 route overlap**：

```text
Historical route:
  positive:       "去年那个 bug 怎么解决的？"
  counterexample: "这个 bug 怎么解决？"       → current
  boundary:       "刚才那个 bug 怎么解决？"   → thread + current
```

- intent → route_target 是到 capability / 数据源的映射，不是 intent → Agent 映射（§9）。

## 4. 混合路由：确定性信号优先

确定性信号（0 额外成本、可测、优先级高）：

```text
文本规则：     "刚才/这个会话/本次" → scope=thread
              "以前/之前/上次/去年" → temporal=historical
              "忘掉/别再提"        → forget route
请求 metadata：thread_id / user_id / project_id（显式携带）
              UI state / API route / client 上下文
会话状态：     active task 存在 → task route 优先
```

LLM structured understanding 只处理规则未覆盖的语义部分。冲突时**确定性信号优先**——现有「本地关键词短路兜底 LLM 判定摇摆」即此原则的实例。Level 3 完整形态：

```text
Hard Rules / Metadata → Structured LLM Understanding → Validation → Capability Routing
```

## 5. Ambiguity 与 Fail-Closed

Hard Invariant（architecture §0.10）：**Intent ambiguity must never widen information visibility.**

"之前那个方案呢？"无法确定是当前 thread 还是历史 cross-session → 默认解析到 **current / narrower scope**（当前 thread），不搜索用户全部历史。这与 scope fail-closed（无 project 上下文 → project 记忆零可见，architecture §4）同族：不确定时收窄，绝不扩大。

澄清策略：`ambiguity.material=true` 才向用户澄清——material 指显著影响**权限 / scope / 副作用 / 工具操作 / 结果正确性**。低 routing_confidence 本身不触发提问；每次低置信就问 = 把路由失败转嫁给用户。

## 6. Confidence 语义

`routing_confidence` 是 **LLM self-reported score，不是 calibrated probability**——不得直接当真实概率消费。决策综合：

```text
rule hit            确定性信号是否命中
schema validity     structured output 是否合法
route margin        top-1 与 top-2 的分差
consistency         同请求多次路由的一致性
retrieval evidence  召回结果是否支撑该 intent
eval calibration    真实标注集上的校准
```

阈值通过真实 eval 校准（testing.md §8 Routing Quality），不写死 "confidence < 0.7 = ask user" 之类的架构真理。

## 7. Capability Routing 与 Just-in-Time Context

Request Understanding 最重要的输出不是 intent name，是 **capability_plan**——本轮到底需要哪些能力：

```yaml
capability_plan:
  session_history: true       # 当前 thread 窗口/摘要
  user_memory: false          # global scope 记忆
  project_memory: true
  raw_history: false          # cross-session raw 检索
  rag: false
  tools: false
  specialist_agent: false
  # memory 键可按 memory_type 细分（semantic/episodic/procedural），
  # 与 architecture §9.5 context_plan 的分型块对齐；简单项目用粗粒度键
```

`false` → **节点物理跳过**（architecture §6 能力门控；needs_memory / needs_knowledge / needs_tools 是其最小键集），继续保持「不要全部查完再告诉模型忽略」：

```text
"你好"                              → 全 false：0 retrieval / 0 tool call
"上次这个项目 migration 为什么失败？" → project_memory / episodic / raw_history ON，
                                       rag maybe，tools OFF
```

三分职责，**不得混成一个模块**：

```text
Routing 决定：        可能需要什么（capability namespace）
Retrieval 决定：      真正相关什么（architecture §4）
Context Planner 决定：最终让模型看到什么（architecture §9.5）
```

与 Progressive Disclosure（architecture §9.4）结合：routing 选择 **available capability namespace**（目录），不注入能力内容本身——真正需要时再 discover → retrieve → use：

```text
available:
  memory/search
  project/history
  knowledge/search
  tools/calendar
```

## 8. 与 Memory / Context 的集成（收编，不重建）

### 8.1 收编表——现有机制 → request model，实现不变

| 现有机制（architecture.md） | 收编为 | 实现 |
|---|---|---|
| 会话范围路由（§4 元问题二分） | scope_intent + temporal_intent | 不变（LLM + 关键词兜底 = Level 3 实例） |
| Normal / Historical 双路由（§4） | temporal_intent → route 选择 | 不变（normal 默认；显式历史意图才 historical） |
| 能力门控 needs_memory / knowledge / tools（§6） | capability_plan 最小键集 | 不变（false 物理跳过） |
| Writer 预判 memory_write_candidate（§3） | request_model 候选标记 | 不变（仍过 Writer 全部门控） |
| forget 请求识别（§5） | 确定性 rule → forget route | 不变 |
| Planner 输入 query_type / task_complexity（§9.5） | request_model 作为输入来源 | 不变（Planner 消费，不重新判定） |
| scope fail-closed（project，§4） | 与 §0 / §5 的 fail-closed 同族 | 不变 |

Routing 是统一入口：数据源选择（current messages / session summary / digest / raw history / RAG / tools）由 scope_intent + temporal_intent + capability_plan 共同决定；Visibility 与 Historical Route 的实现一字不动。

### 8.2 与 Memory Writer 的边界

"记住我喜欢 Python" → `memory_write_candidate: true` → **仍必须进 Writer Gate**（source validation / 敏感信息检查 / dedup / conflict / scope / confidence / authority，architecture §3）。Intent 不得绕过 Writer；Router 不得直接写库、不得直接返回 Memory。

### 8.3 与 Context Planner 的连接

Planner 输入 = request_model（intent / scope / temporal / information_needs / capability_plan / task_complexity）+ 模型窗口等约束 → 输出块与 token（architecture §9.5）。Planner 消费 request_model，不重新做请求理解。

### 8.4 与 Stable Prefix 的边界

routing output（intent / confidence / route result / 当前 tool result）是 **Dynamic Runtime State** → 进 Dynamic Tail 或 request-scoped structured state；**禁止每轮塞进 Stable Prefix**（architecture §6 三段布局；testing 场景 23）。

## 9. Handoff vs Agent-as-Tool（Level 5）

| | Handoff | Agent-as-Tool |
|---|---|---|
| 控制权 | specialist 接管后续处理 | manager 保持控制 |
| 适用 | 真正切换责任主体 | bounded subtask，结果回流 manager |
| 上下文 | specialist 拥有后续对话 | manager 拥有 |

启用前提：不同任务**真的**需要不同 prompts / tools / permissions / context / expertise——只差 prompt 不差权限/工具时，用 routing + 不同 context 组装即可，不起 Agent。禁止把 intent label 机械映射成一个独立 Agent。Multi-Agent 共享记忆仍按 architecture §10.3（不预抽象）。

## 10. Routing Trace 与观测

memory_trace（architecture §9.9）扩展 routing 段（或独立 routing_trace），让「为什么这么路由 / 为什么跳过 / 为什么澄清」可读——它是 testing.md 场景 24–28 的数据源：

```yaml
routing_trace:
  input_signals:            # metadata / 会话状态（不含全量 raw text）
  metadata_signals:
  rule_hits: []             # 命中的确定性规则
  llm_router:
    invoked: true
    decision:               # structured output 摘要
  parsed_request:           # request_model 摘要（intent/scope/temporal/information_needs）
  candidate_routes: []
  selected_capabilities: []
  ambiguity:
  fallback_reason:          # 降级 / 兜底路径的原因
  authorization_checks: []  # 被授权层拒绝的建议（Routing ≠ Authorization 的证据）
  downstream:
    retrievals_run: []
    tools_run: []
```

retention：**不永久记录 raw user text**，除非产品 retention / privacy 明确允许；按 dev / debug / sampling 分级存储（同 architecture §9.9）。
