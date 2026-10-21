# Skill Evals：触发样本与工作流 Golden Trace

维护者自查用：修改 SKILL.md / references 后跑一遍，防止触发退化和工作流漂移。宿主代理**不自动执行**本文件——它是给人 / CI 的验收清单，不是运行时依赖。

## 1. 触发测试（正样本：应激活本 skill）

| # | 输入 | 期望 |
|---|---|---|
| P1 | "Help me design the memory and context system for this agent." | 触发，进 BUILD |
| P2 | "帮我设计这个 Agent 的长期记忆和上下文系统。" | 触发（中文触发词），进 BUILD |
| P3 | "Why is this agent leaking information between conversations?" | 触发，进调试工作流 |
| P4 | "Agent 记错了用户信息，怎么修？" | 触发（症状式描述），进调试工作流 |
| P5 | "Audit the memory architecture in this repository." | 触发，进 AUDIT（只读） |
| P6 | "这个 Agent 该怎么理解用户请求、识别意图、做能力路由？" | 触发，读 request-understanding.md |
| P7 | "给记忆系统写测试和评估指标。" | 触发，读 testing.md |

## 2. 触发测试（负样本：不应激活，易误伤域）

| # | 输入 | 不触发的原因 |
|---|---|---|
| N1 | "帮我记住明天下午开会。" | 个人提醒需求，不是 Agent 记忆系统开发 |
| N2 | "这段 C++ 代码有 memory leak，帮我查。" | 内存泄漏 ≠ agent memory（词形碰撞） |
| N3 | "ChatGPT 的记忆功能在哪里开？" | 终端用户使用问题，非系统设计 |
| N4 | "写一个基于艾宾浩斯遗忘曲线的背单词 App。" | 产品需求，"记忆"是业务概念非 agent 架构 |
| N5 | "RAG 的原理是什么？"（无系统设计语境） | 纯知识问答；若语境变为"给我的 Agent 加 RAG"则应触发 |

判定原则：触发词命中只是必要条件，语境必须是**开发 / 设计 / 审计 / 调试 Agent 的记忆、上下文或路由系统**。

## 3. 工作流 Golden Trace（每工作流一条最小期望）

### BUILD

输入："从零给一个多用户学习规划 Agent 设计记忆系统。"

期望序列：
1. 进入前检查 `AGENT_MEMORY_DESIGN.md`（不存在 → 新建约定生效）；
2. Capability Scope Decision 输出 task_capabilities 三项，每项 status + reason（本例 memory=required、request_understanding=relevant、context=required）；
3. DISCOVER 优先从代码 / PRD 推断，不发问卷；
4. DESIGN 五类产出（layers / memory_types / representation / advanced_patterns / routing_strategy）逐项 status + reason，敢于输出 not_needed；
5. `architecture_decisions` 覆盖所有 not_needed；
6. IMPLEMENT 后对账 `AGENT_MEMORY_DESIGN.md`，EVALUATE 给出 evaluation_plan（required / optional / skipped_tests 带 reason）；
7. Definition of Done 六项逐条核验后才交付。

### AUDIT

输入："帮我看看这个仓库的 memory 架构设计得怎么样。"

期望序列：只读侦察（INSPECT 八检查点）→ 对照 §0 Hard Invariant 逐条判定 → CHECK MAPPING / ROUTING / WRITE / READ / CONTEXT PATH → SELECT TEST MATRIX → 输出 `{gaps: [{severity, violated_invariant, location, fix_hint}], test_matrix, priority}`。全程零代码修改；用户追加"修一下"才转调试工作流（从 REPRODUCE 起步，除非证据链完整）。

### DEBUG

输入："Agent 在 B 会话回答了 A 会话的内容。"

期望序列：INSPECT 只读 → REPRODUCE 构造最小对话 + failing test（修复前必须 FAIL；无法稳定复现则停在此）→ TRACE 按 CASE R / A–F 定位 first contamination point → DIAGNOSE 结构化结论（含 evidence 与 confidence）→ PATCH 最小修改且动手前说明 → VERIFY 七项核心回归 + 能力回归全绿。跳阶段（没复现就改码）= FAIL。

## 4. 回归口径

- 改 frontmatter description / 触发词 → 重跑 §1–§2 全部样本；
- 改工作流阶段定义或产出模板 → 重跑 §3 对应 trace；
- 只改措辞 / 修错字 → 不要求重跑。
