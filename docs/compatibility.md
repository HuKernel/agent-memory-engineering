# Cross-Platform Compatibility

最高原则：**One canonical Skill → Multiple host adapters → No duplicated logic → No platform lock-in.**

## 单一内容源

`skills/agent-memory-engineering/`（SKILL.md + references/）是唯一内容源。Claude 与 Codex 的安装目标（`~/.claude/skills/`、`~/.agents/skills/`）都是 installer 生成的 **installation artifact**，不是开发源。更新核心 Skill 后：

```bash
./installers/install.sh --target all --force   # 同步两端（保留时间戳备份）
python scripts/validate.py --check-install ~/.claude/skills
```

禁止手工维护 `.claude/skills/` 或 `.agents/skills/` 下的副本。仓库内也不出现这两类目录（demo 需要时由 installer 动态生成，不入库）。

## Manifest 取舍（为什么只有两个 manifest）

| 文件 | 状态 | 理由 |
|---|---|---|
| `plugin.json`（根部） | **保留** | Agent Plugins 1.0.0 portable manifest（`$schema: agent-plugins.org/schemas/1.0.0`）。同时是 **Codex 官方推荐的可复用分发格式**（universal plugin directory），服务所有 Agent Plugins 兼容 host。 |
| `.claude-plugin/plugin.json` | **保留** | Claude Code 原生 plugin manifest（唯一必填字段 `name`；`skills: "./skills"` 引用不复制内容）。支持 `claude --plugin-dir .` 与 marketplace 安装。 |
| `.codex-plugin/plugin.json` | **不创建** | 当前 Codex 官方规范中不存在该专有格式——Codex 的 plugin 分发就是根部 Agent Plugins `plugin.json`。创建它属于凭空发明非标准文件，只增加漂移面。 |

## 版本同步

`VERSION` 是唯一版本源；两个 manifest 的 `version` 必须与之一致，`scripts/validate.py` 第 [5] 项强制校验。

## Canonical Skill 的 host neutrality

SKILL.md 正文不出现 "Claude 的 X 工具 / Codex 的 Y 命令" 类宿主专有引用，使用能力语义（读代码 / 追调用链 / 跑测试 / 改实现）。能力不可用时降级为 implementation-ready 计划，不虚构执行（见 SKILL.md IMPLEMENT 节 Host capability 语义）。

frontmatter 仅含开放标准必需的 `name + description`；Codex 专属 `agents/openai.yaml` 当前 YAGNI 未启用（需要时加入 skill 目录，Claude 忽略之）。

## Smoke Tests（发布前手动执行）

安装后分别在两个宿主验证发现与触发：

1. Claude Code：新会话输入 “帮我设计这个 Agent 的长期记忆和上下文系统。” → 预期 agent-memory-engineering skill 被触发
2. Codex：`/skills` 能看到 agent-memory-engineering；`$agent-memory-engineering` 显式调用成功；同句测试隐式触发

## 自动触发正负样本

两端都按 `name + description` 判定适用性，测试清单：

**Should Trigger**

- “给我的 Agent 设计长期记忆。”
- “检查为什么我的 AI 会串会话。”
- “帮我优化 context management。”
- “给现有 memory system 做 audit。”
- “为什么 agent 总记错用户信息？”

**Should NOT Trigger**

- “帮我写一个 React Button。”
- “解释 Python decorator。”
- “帮我修改 CSS。”

误触发率高时优先优化 SKILL.md 的 `description`（前置触发词），不把路由规则塞进正文。

## 与本提示词示例不同之处

- 未创建 `.codex-plugin/plugin.json`（官方无此格式，理由见上表）。
- Codex 用户级路径使用 `$HOME/.agents/skills/`（官方现行标准），非 `~/.codex/skills/`。
- License 未指定 → 生成 `LICENSE-TODO.md` 提醒，不代做法律选择。
- `scripts/check-version-sync` 未单独建——版本同步并入 `scripts/validate.py`，避免文件碎片化。
