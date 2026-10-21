# Changelog

本文件记录仓库打包形态与核心方法论的显著变更。格式参考 Keep a Changelog，版本遵循 SemVer。

## [2.0.0] - 2026-10-21

规范性整改 + 渐进式披露重构 + 仓库结构扁平化。**方法论语义不变**（Hard Invariant、31 场景、三支柱管线、路由分级均保持原样）——本版修的是载体合规性、文档一致性与未兑现承诺。

### Changed

- **仓库结构扁平化**：`skills/agent-memory-engineering/` → `skills/`（去掉单 skill 仓库的多余目录层）。skill 名称取自 SKILL.md frontmatter 的 `name` 而非目录名，skills CLI 发现 `skills/` 容器下的 SKILL.md 且安装时按 `name` 重建目标目录（实测：源在 `skills/`，装到 `.claude/skills/agent-memory-engineering/`，references/ 与 evals/ 相对路径不变）——故此变更不影响安装与触发。README 补「为什么是 `skills/`」的说明

### Fixed

- **`description` 超过 Agent Skills 规范 1024 字符硬上限**（原 1172 字符）——超限可能导致 skill 在 Claude Code / Codex 中不被加载或触发失败。压缩至 676 字符，保留能力动词 + 中英触发词 + 症状式描述（"agent 记错了" / "跨会话泄漏"）
- **铁律 ↔ Hard Invariant 编号语义错位**：SKILL.md 铁律 1–9 与 arch §0.1–§0.10 是两套独立编号，铁律 6（证据优先级）实际对应 arch §0.2 而非 §0.6，跨文档"铁律 N"引用会查错。现于 SKILL.md 铁律条目内标注对应 arch §0 编号，arch §0 每条反向标注「= 铁律 N」，并在两处各加一段**编号约定说明**（两份清单正交、不是父子关系）
- **`request model` 顶层键名三义混用**：`request_mapping` / `request_understanding` / `request_model` 在 SKILL.md 与 ru §1 之间不一致。现将 ru §1 的 `request_understanding` 定为 canonical 顶层键，并显式禁止其余两种写法
- **`capability_plan` 键集缺 canonical 标注**：ru §7 注释允许按 memory_type 细分但未给替换规则，`user_memory` 与 `semantic_memory` 并存会产生权威歧义。现标注 8 键为 canonical 最小集，细分键**替换**原键不并存，并列出 `model_selection` / `reasoning_effort` 为可选扩展
- **跨文档裸 `§N` 引用**（如 SKILL.md 内写 `§9.6` 实指 architecture.md）易被误读为本文章节——现全文统一使用 `arch` / `ru` / `test` / `tpl` / `wf` 缩写前缀，SKILL.md 顶部加「文件缩写」说明并明示"跨文档引用必须带文件名"

### Added

- **MIGRATION 工作流**——兑现 description 与 README 长期宣称的"全生命周期含迁移"承诺。此前"迁移"只存在于 arch §8 的 4 行 Phase 1/2/3 描述，**无任何触发路径**。新工作流补齐 INSPECT → 对齐目标 → 幂等迁移 → VERIFY 四阶段，并把"旧行 NULL 不得自动解释为 global、证明不了 fail closed"提为硬约束
- **`references/workflows.md`**——四工作流的执行细则（DISCOVER/MODEL/DESIGN/MAP/IMPLEMENT/EVALUATE、MIGRATION、AUDIT 11 项检查、DEBUG 各阶段禁令），按需加载
- **`references/templates.md`**——产出模板库（Capability Scope Decision / DESIGN 五类 / information_mapping / architecture_decisions / memory_system_blueprint / evaluation_plan / DIAGNOSE / AUDIT 报告 / AGENT_MEMORY_DESIGN.md 骨架）
- `evals/evals.md` 补 P8（MIGRATION 触发正样本）与 MIGRATION golden trace，并新增 §5 结构校验清单（description ≤1024、SKILL.md 体量、裸 § 引用、孤儿文件检查）

### Changed

- **SKILL.md 瘦身至 ~6.3k token / 150 行**（原 ~12k token / 499 行，超出规范建议值 <5000 token 的 2.4 倍）。做法是标准 progressive disclosure：原「核心模式速查」整段是 references 的镜像（且与 SKILL.md 自己"细节以 references 为准"的规矩冲突），替换为**症状定位索引表**（12 条症状 → 目标章节）；大段 YAML 模板移入 `references/templates.md`；工作流详细步骤移入 `references/workflows.md`
- 术语约定段落由 600 字符密排改为表格，检索性提升
- `SKILL.md` 新增「文件缩写」约定与「铁律 ↔ Hard Invariant 编号约定」两段说明，消除编号歧义
- `references/architecture.md` 顶部新增「按需读取」导航表（任务类型 → 应读章节），替代拆文件方案
- README 仓库结构图补 `workflows.md` / `templates.md`，并说明渐进式披露分工；能力表补 MIGRATION 行
- SKILL.md 四个工作流标题统一为 `###` 同级（`BUILD` / `MIGRATION` / `AUDIT` / `DEBUG`），总览表保留阶段与硬约束摘要

### Unchanged

Hard Invariant（arch §0 十条）、七层模型、memory_type taxonomy、Writer 双 candidate source + lineage、Forget/tombstone、Normal/Historical 双路由、Procedural Authority Boundary、Structured Core + Raw History、Context Stability 三段布局、Level 0–5 路由分级、31 个测试场景与三层测试体系——**语义与编号均未改动**。

### 评估后未采纳

- **拆分 `references/architecture.md`**（22k token）——评估后不采纳。Core（§0–§7）与 Advanced/Optional/Sources（§8–§11）的外部引用频次几乎持平（19 : 17），说明多数任务跨两侧命中，拆文件的净收益为负；且需改动 44 处跨章节引用，引入漂移风险。改为在文件顶部加「按需读取」导航表，同等收益、零漂移。

## [1.9.0] - 2026-10-21

对照 2024–2025 路由研究与工业实践（RouteLLM / Aurelio & vLLM Semantic Router / FrugalGPT / Query Routing for RAG）补强 Request Understanding 支柱的实现层与工程闭环；Hard Invariant 不变。

### Added

- **Level 1.5 语义向量路由**（request-understanding.md §2 分级表新档）：route = utterance 样本集 embedding 索引 + 最近邻匹配与阈值触发——语义泛化但零 LLM call、毫秒级；填补 Level 1（规则）与 Level 2（LLM）之间的空档
- **Router vs Cascade 与判定器级联**（request-understanding.md §2 新增段落）：与 Level 分级正交的成本维度——判定本身遵循 simplest sufficient（规则 → 向量 → 小 LLM → 大 LLM）；capability_plan 可选扩展 model_selection / reasoning_effort 键（"when to reason"）；不变式：降级判定不放宽可见性、升级判定不授予权限
- **路由器数据闭环**（request-understanding.md §3 扩展）：冷启动 / 样本即索引（三类样本直接 embedding 化）/ 线上误判回流 hard negatives / paraphrase 扩增 / 偏好数据 / 评估集先行
- **Router 评估方法**（testing.md §8 新增块）：golden set 构造（6:2:2 配比，boundary 决定区分度）、confidence 校准曲线（reliability diagram）、quality retention per cost、语义缓存命中率

### Changed

- architecture.md §11 学术来源补"路由与级联"条目（RouteLLM / FrugalGPT / Semantic Router ×2 / Query Routing for RAG）

## [1.8.0] - 2026-10-21

吸收《深入理解 AI Agent》v1.2 Chapter 3 的未覆盖增量；Hard Invariant 不变。

### Added

- **能力成熟度三层次评估框架**（testing.md §8 开篇）：L1 基础回忆 / L2 多会话检索（多片段联合推理 + 时间感知，映射到既有场景）/ L3 主动服务（预见性帮助，产品级目标）；八项能力参照与 LLM-as-a-judge 评估口径（仅访问记忆不可回看原文），衔接 §12 公开基准
- **Executable Memory / User as Code**（architecture.md 新增 §10.4）：可执行代码记忆介质——只增事实日志（WAL）+ 周期性带类型 checkpoint；聚合统计 / 交叉冲突发现 / 约束执行三大确定性优势（检索式文本 6–43% → 代码 ~99%）；适用判定与代价（需代码工程支撑，杂项事实无优势，文本表示的专项补充非替代）；§2 补表示介质由外及内连续谱（文本 → 代码 → 参数化前沿不入默认集）
- **日志 / trace 侧 PII 脱敏**（architecture.md §7）：与写入侧拦截互补的"不留痕"层——本地小模型检测（脱敏数据不上云）+ 正则/LLM 混合分级（高吞吐正则先行）

### Changed

- architecture.md §10.1 Graph Memory 补分层互补策略（自然语言为主 + 结构化元数据为辅；实体消歧为图谱不可替代场景）与三元化语义降级风险
- architecture.md §2 补 Memobase 式槽位化画像配置与 episodic 时间 × 主题多维组合检索；§9.4 补文件系统范式生产例证（OpenViking L0/L1/L2 三层按需加载、宿主目录式 memory tool）
- architecture.md §11 Chapter 3 条目更新 v1.2 增补吸收清单

## [1.7.0] - 2026-10-21

吸收《深入理解 AI Agent》v1.2 Chapter 2 的未覆盖增量；Hard Invariant 不变。

### Added

- **Agent 状态栏（Status Bar）**（architecture.md §6 新增小节）：末尾 user-role 元信息注入通道——"上下文学习像检索不像推理"（只有一半的检索引擎），隐式状态显式化；代码维护三原则（勿用 LLM 批量统计 / 删原文前确认覆盖所有问题维度 / 准确率当一线生产指标防投毒）；两种更新实现（每轮替换 vs 持久追加）的 KV Cache 代价取舍；键值对形式、增量发送；标注铁律 7 实时 SoT 的注入形态。量化锚点来自 Context Distillation 研究（弱模型 +40~54pp / 强模型思考 token 降一个数量级）
- **隔离优于压缩：Sub-agent Context Isolation**（architecture.md §6 新增小节）：大体积探索类中间信息委派子 Agent 消化、只回传结论性摘要，主上下文与前缀缓存零污染；任务描述必须自包含；审计/回放场景不适用（走 Raw History Archive）
- **压缩策略分级**（architecture.md §5 补强）：五层兜底（工具结果预算控制 → 噪声直接删除 → API 层 context editing → 归档式摘要 → 全量压缩 + 连续失败熔断器）；80% 阈值批量触发 + `[COMPRESSED]` 防重复；上下文感知压缩（query 意图进压缩提示）；显式压缩保留优先级清单（架构决策/验证状态/未决 TODO 不摘要；标识符原样保留）
- **Context Rot**（architecture.md §6 Attention Budget 补）：腐化（装得下但找不到）≠ 溢出（装不下）；识别信号与处置（压缩/隔离而非换长窗口模型）

### Changed

- testing.md §8 Context Quality 新增 **Status Bar Accuracy** 指标（状态栏元信息与真实状态偏差，>10% 可能比不带更糟）
- SKILL.md 核心模式速查「上下文组装」补状态栏 / 子代理隔离 / 五层压缩要点；architecture.md §11 Chapter 2 条目更新 v1.2 增补吸收清单

## [1.6.0] - 2026-10-21

对照学界基准与业界实践（LongMemEval / LoCoMo / Anthropic memory tool / 认知架构）的外围补强；Hard Invariant 与核心方法论不变。

### Added

- **External Benchmark Calibration**（testing.md 新增 §12）：内部能力 → 公开基准子集映射（knowledge updates / abstention / session tracking / End-task Delta ↔ LongMemEval(-V2) / LoCoMo）；基准是 Recommended Default 校准工具，不构成新 Hard Invariant，与内部 invariant 冲突时 invariant 优先
- **Skill 自带 evals**（新增 `evals/evals.md`）：触发正样本 7 条 + 易误伤负样本 5 条（memory leak / 个人提醒等词形碰撞域）+ BUILD / AUDIT / DEBUG 三工作流 golden trace；维护者改 skill 后自查用，宿主代理不自动执行
- **Memory Interface Pattern**（SKILL.md MAP 阶段）：pipeline-injected / tool-based / platform-managed 三形态选型表——接口形态决定铁律 9 的 enforcement point；任何形态下 Writer 门控与 Visibility 硬过滤不降级
- **Attention Budget 与位置敏感放置**（architecture.md §6 新增小节）：token 预算管"放多少"、attention 管"看得见多少"；关键约束放头尾、低优先级放中段；平台 context editing 与 tombstone / SummarySegment 不可变的交互边界
- architecture.md §11 新增**学术来源锚点**：MemGPT / Generative Agents / ACT-R / Mem0 / Zep·Graphiti / A-MEM / MemOS / Reflexion / Voyager / LoCoMo / LongMemEval / Anthropic Memory Tool，逐条标注与本仓库模式的对应及取舍（如 MemOS 判定为产品架构不引入）

### Changed

- architecture.md §4 权重理由显式化 **usage-based activation**：强化次数 + 使用频次（访问历史）与 recency（内容时新）正交；`access_count / reinforcement_count / last_confirmed_at` 已有字段支撑检索期递增，不新增 schema
- SKILL.md references 导航与 EVALUATE 指向 testing.md §12；README 结构图补 evals/

## [1.5.0] - 2026-10-21

流程机制补强（借鉴 Agent Skill 交互式架构师模式），方法论内容不变。

### Added

- **Design Artifact Protocol**：BUILD 设计产出（Capability Scope Decision / 选层选型 / architecture_decisions / blueprint）统一持久化到项目内 `AGENT_MEMORY_DESIGN.md`（单一事实来源）；进入 BUILD 先检查该文件决定续作或新建；文档先于代码，IMPLEMENT 收尾对账；调试 PATCH / AUDIT 修复改变设计决策时同步更新
- **BUILD 完成定义（Definition of Done）**：六项交付检查（落盘对账 / status+reason 完整性 / not_needed 决策覆盖 / evaluation_plan 完整性 / 铁律复核 / Blueprint 完整性）
- **references 导航**：三个 reference 的 § 地图 + 不确定位置时的关键词 Grep 查找方式 + 冲突裁决（SKILL.md 管路由与约束，细节以 references 为准）

### Changed

- README 核心方法论清单补 Design Artifact Protocol

## [1.4.0] - 2026-09-16

Final Freeze Consistency Patch（v2 freeze）——修复四文件间生命周期 / 能力模型 / Debug / 测试一致性，不新增架构 Pattern。

### Added

- capability_plan 新增 canonical 键 `external_state`（runtime capability），与 information_needs 的 `realtime_state`（information need）明确区分；external_state ≠ tools（由技术栈映射决定）；新增"账户余额"示例与 Context Planner 对齐规则（request-understanding §1/§7/§8.3、architecture §6/§9.5）
- DEBUG Root Cause 分类升级为 **CASE R / A–F**：Routing 是独立 first failure point（downstream symptom 不改判分类）；DIAGNOSE 增加 routing_evidence（capability-selective）；PATCH 优先级更新为 Authorization / Scope Isolation > Request Routing > Retrieval Filter > …
- AUDIT 新增 **CHECK ROUTING PATH**（11 项检查；Routing Path 查"为什么选择这些能力"，Read Path 查"如何安全读取数据"，不重复 Memory Visibility 检查）
- BUILD：开场定位升级为 Agent Runtime Information Architecture（不要求三模块同时重建）+ **Capability Scope Decision**（task_capabilities，任务范围判断非 runtime schema）；MODEL 升级为 **Runtime Requirement Modeling**（Request Modeling + Information/Memory Modeling 两个 capability-selective 子模型，No consumer → No field）
- testing.md 新增场景 29（Multi-Intent Composition）/ 30（Routing Injection，复用 retrieved content = data, not authority）/ 31（Paraphrase Robustness）；Routing Quality 补 5 指标（Capability Precision / Capability Recall / Paraphrase Consistency / Unnecessary Retrieval Rate / Wrong Tool Activation Rate）；End-task Delta 增加 Router 三档对比（No Dedicated Router vs Router Enabled vs Oracle Route）

### Changed

- Level 3 措辞"生产推荐默认"→"语义复杂场景的常见生产形态"（避免 simplest sufficient router 被诱导升级）
- 「按需求选路径」拆出 Intent / Memory / Context / Integrated 四类独立入口（Context 不再只能从 Memory BUILD 间接进入）；Routing bug（意图识别错误/路由错误/工具选错/能力误激活/错误跨会话历史检索）明确进入 DEBUG
- testing.md 标题改为「Agent Runtime Information Architecture 测试方案」（覆盖三支柱，只改定位不重构正文）

## [1.3.0] - 2026-09-16

### Added

- **Request Understanding & Intent Routing**：新增 `references/request-understanding.md` 模式库——多维 Request Model（intent × scope × temporal × information needs × action × capability_plan，正交、多意图）、Routing 分级 Level 0–5（simplest sufficient router）、Intent Taxonomy 从产品推断（closed/open/hybrid + unknown 兜底 + positive/boundary/counterexample 样本）、混合路由（确定性信号优先 + 结构化 LLM 理解）、Ambiguity fail-closed（仅 material 才澄清）、confidence 语义（自报分数非校准概率，阈值经 eval 校准）、Capability Routing（false 物理跳过）、Handoff vs Agent-as-Tool、routing_trace（不永久记录 raw user text）
- 统一 Runtime Pipeline：architecture.md 开篇新增「Runtime Information Architecture」集成图（Request Understanding → Scope/Authorization Guard → Capability Activation → Memory/Knowledge/Tools/External → Context Planner → LLM → Update → Evaluate）
- Hard Invariant 新增两条：§0.9 Router 只选择候选不授予权限（Routing suggests. Authorization decides. Visibility enforces.）、§0.10 Intent 歧义 fail closed
- testing.md 新增场景 24–28（路由歧义 fail-closed / Routing ≠ Authorization / 能力门控物理跳过 / 多维请求分解 / unknown intent 兜底）与 §8 Routing Quality 指标组（Routing Accuracy / Clarification Rate / Silent Mis-route Rate / Router Overhead / confidence 校准）

### Changed

- 现有路由能力**收编**进 Request Understanding 统一入口、实现不变：会话范围路由与 Normal/Historical 双路由的触发判定 ← scope_intent + temporal_intent；能力门控 needs_memory/needs_knowledge/needs_tools ← capability_plan 最小键集；Writer 预判 memory_write_candidate、forget 识别、Context Planner 的 query_type/task_complexity 同步对齐（收编表见 request-understanding.md §8.1）
- SKILL.md：标题与简介升级为 Agent Runtime Information Architecture 三支柱；铁律新增第 9 条（Routing 只建议不授权）；BUILD 的 DISCOVER 增加 routing_requirements + Intent Space 推断、DESIGN 增加 Routing Strategy 选型、EVALUATE/VERIFY 纳入场景 24–28；memory_trace 扩展 routing 段
- SKILL.md description 触发词扩展：intent routing / 意图识别 / 意图路由 / request understanding / agent runtime architecture
- architecture.md §11 设计来源补充：原书 Chapter 1（Agent = LLM + Context + Tools）、Chapter 7（Agent Evaluation），以及主流工程共识（Anthropic Building Effective Agents / Effective Context Engineering、OpenAI Agents SDK handoffs & guardrails、LangGraph routing / structured output / conditional edges）

## [1.2.0] - 2026-09-16

### Changed

- 简化为标准 Agent Skills 仓库：`npx skills add HuKernel/agent-memory-engineering` 一键安装（no clone / no manual copy / no custom installer）
- README 重写为一键安装优先（Claude Code / Codex / 双端非交互命令 + usage 示例）

### Removed

- 自定义安装器（`installers/`）、plugin manifests（`.claude-plugin/`、根部 `plugin.json`）、`scripts/validate.py`、`docs/`、`VERSION`——skills CLI 已负责发现/安装/更新，不再重复造轮子
- 误加的 `LICENSE-TODO.md`——仓库自 Initial commit 起即为 MIT License

### 核心内容

- `skills/agent-memory-engineering/` 布局与内容自 1.1.0 起未变（skills CLI 标准 `skills/` 发现布局）

## [1.1.0] - 2026-09-16

### Added

- 跨平台打包：canonical Skill 迁移至 `skills/agent-memory-engineering/`（单一内容源，Claude Code 与 Codex 共用）
- Claude Code plugin manifest（`.claude-plugin/plugin.json`）与 Agent Plugins portable manifest（根部 `plugin.json`，同时是 Codex 分发格式）
- 跨平台安装器：`installers/install.sh`（macOS/Linux/Git Bash）、`installers/install.ps1`（Windows）、`uninstall.sh`；支持 `--target claude|codex|all`、`--scope user|project`、`--force`、`--link`
- 打包一致性校验 `scripts/validate.py`（frontmatter / 链接 / manifest / 版本同步 / 安装产物比对）
- SKILL.md 新增 Host capability 语义（能力不可用时降级为 implementation-ready 计划，不虚构执行）
- `docs/`：claude.md、codex.md、compatibility.md（manifest 取舍、smoke test、触发正负样本）
- VERSION / CHANGELOG / LICENSE-TODO

### Changed

- README 重写为以安装体验为中心（Claude / Codex / Windows / 手动安装）

### 核心方法论（此前完成，随 1.1.0 一并冻结）

- 七层记忆模型、semantic/episodic/procedural 分类（decision 走 domain）
- Writer 双 candidate source + Raw History Source Lineage + promotion_source_allowed
- Forget/tombstone 注入期屏蔽、Normal/Historical 双路由、retention 前提
- Procedural Authority Boundary（mandatory guardrail，scope ≠ authority）
- Structured Core + Raw History、Memory Representation Strategy、Context Stability 三段布局
- 三层测试体系：Universal Hard Invariant / Capability Hard Tests（23 场景）/ Quality Metrics
- 《深入理解 AI Agent》（李博杰）Context Engineering / User Memory 思想工程化融合（见 architecture.md §11 Design Sources）
