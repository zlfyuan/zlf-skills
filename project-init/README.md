# project-init

> 自动检测并初始化编程项目 —— 让每个新 clone 的仓库秒级具备 Claude / Codex 协作所需的基础设施。

## 它解决什么问题

新 clone 一个仓库后，每次都要手动：

- 写 `CLAUDE.md` / `AGENTS.md`
- 配 `.claude/settings.local.json` 权限
- 跑 `codegraph init`
- 建 `.claude/progress/` 状态追踪目录
- 决定哪些文件进 `.gitignore`

`project-init` 把这套流程打包成一个**只增不删**（additive-only）的脚本组合，幂等可重跑。

## 触发时机

| 触发方式 | 入口 |
|---------|------|
| **SessionStart hook**（推荐） | 每个会话开始时自动检测 + 初始化 |
| **手动关键词** | `init project` / `setup project` / `初始化项目` / `项目初始化` |
| **直接跑脚本** | `bash scripts/setup-project.sh <dir>` |
| **自主开发循环** | `/loop` / `/goal` —— 强制执行 `.claude/progress/` 状态追踪 |

详见 [`SKILL.md`](./SKILL.md) 的"工作流程"章节。

## 产物结构

初始化完成后，目标项目会得到：

```
<your-project>/
├── CLAUDE.md                     # Claude Code 指令（含 Plan 镜像规则）
├── AGENTS.md                     # Codex / 其他 agent 指令
├── .gitignore                    # 自动加入 .claude/ .codex/ .codegraph/ 等
├── .claude/
│   ├── settings.local.json       # 默认权限 + plansDirectory
│   ├── rules/  skills/  commands/  plans/
│   ├── progress/                 # 🌀 自主开发状态追踪
│   │   ├── README.md
│   │   └── problems.md
│   └── .init-done                # 幂等性标记
├── .codex/
│   └── AGENTS.md
└── .codegraph/                   # 由 codegraph init 创建
```

## 脚本清单

| 脚本 | 用途 | 可独立运行 |
|------|------|-----------|
| [`scripts/auto-init.sh`](./scripts/auto-init.sh) | Hook 入口：检测项目类型 + 调度 init | ✗（依赖 hook 配置） |
| [`scripts/detect-code-project.sh`](./scripts/detect-code-project.sh) | 判定当前目录是否是编程项目 | ✓ |
| [`scripts/setup-project.sh`](./scripts/setup-project.sh) | **核心**：执行完整初始化（audit → create） | ✓ |
| [`scripts/teardown-project.sh`](./scripts/teardown-project.sh) | 反向操作：清理 setup 产物（带指纹识别） | ✓ |
| [`scripts/inject-plan-mirror.sh`](./scripts/inject-plan-mirror.sh) | 批量迁移：把 Plan 镜像规则追加到已有项目 | ✓ |
| [`scripts/plan-mirror-rules.sh`](./scripts/plan-mirror-rules.sh) | **共享 lib**：Plan 镜像规则块 + `pmr_inject` 函数 | ✗（仅 source） |

## 关键设计

### Additive-Only（只增不删）

- **已有文件 → 保留不动**。`CLAUDE.md` / `AGENTS.md` / `settings.local.json` 等已存在时**绝不覆盖**
- **`settings.local.json` → 智能合并**。只补缺失的推荐权限，已有权限完全保留
- **已有目录 → 保留不动**。`mkdir -p` 幂等
- 重跑 `setup-project.sh` 是安全的

### Plan 文件镜像（关键）

harness 默认把 plan 写到全局 `~/.claude/plans/<session>.md`（**项目外**，git 无法追踪）。本 skill 在 `CLAUDE.md` / `AGENTS.md` / `.codex/AGENTS.md` 中自动注入**镜像规则**：

> Plan mode 退出之前，必须把 plan 文件从 `~/.claude/plans/` 复制到 `.claude/plans/`（项目级副本，可 git 追踪）

行为矩阵：

| 文件状态 | 行为 |
|---------|------|
| 不存在 | `[NEW]` 创建并嵌入规则 |
| 已含规则 | `[KEEP]` |
| 缺规则（如 `/init` 创建的） | `[KEEP]` + 自动追加规则 ✅ |

详见 [SKILL.md 的 Plan 镜像章节](./SKILL.md#-plan-文件镜像规则自动注入)。

### 自主开发循环（`/loop` / `/goal`）

启用后强制执行 4 条规则：

1. **状态追踪** → `.claude/progress/`（README + stage-NNN + problems）
2. **开发-验证闭环** → 每个模块编译通过才推进
3. **最终用户视角验证** → 端到端走一遍
4. **5 次上限** → 同问题超过 5 次未解 → 记入 problems.md 并跳过

模板见 [`assets/`](./assets/) 目录。

## 资源模板（`assets/`）

| 文件 | 用途 |
|------|------|
| [`assets/progress-README.md`](./assets/progress-README.md) | `.claude/progress/README.md` 的源码模板 |
| [`assets/stage-template.md`](./assets/stage-template.md) | 单个 stage-NNN.md 的格式 |
| [`assets/problems.md`](./assets/problems.md) | 踩坑记录模板 |

## 测试

```bash
bash tests/test-setup-project.sh
```

测试覆盖：fresh project init、idempotent re-run、`.gitignore` 合并、Plan mirror 自动注入等。

## 安装

```bash
# 软链整个目录
ln -s "$(pwd)/project-init" ~/.claude/skills/project-init

# 或只软链到 Codex
ln -s "$(pwd)/project-init" ~/.codex/skills/project-init
```

启用 SessionStart hook 让它自动跑：

```jsonc
// ~/.claude/settings.json
{
  "hooks": {
    "SessionStart": [{
      "type": "command",
      "command": "bash ~/.claude/skills/project-init/scripts/auto-init.sh"
    }]
  }
}
```

## 相关链接

- 详细行为规范：[`SKILL.md`](./SKILL.md)
- 父仓库说明：[`../README.md`](../README.md)
- CodeGraph MCP: https://github.com/colbymchenry/codegraph