# Changelog

本文件记录仓库打包形态与核心方法论的显著变更。格式参考 Keep a Changelog，版本遵循 SemVer。

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
