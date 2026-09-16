# Changelog

本文件记录跨平台打包与核心方法论的显著变更。格式参考 Keep a Changelog，版本遵循 SemVer。

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
