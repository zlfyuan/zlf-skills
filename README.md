# zlf-skills

个人维护的 Claude Code / Codex 技能合集。用于跨机器同步、按需挑选安装到 `~/.claude/skills/`。

## 技能列表

| 技能 | 说明 | 触发方式 |
| --- | --- | --- |
| [`karpathy-guidelines/`](./karpathy-guidelines/) | 来自 Andrej Karpathy 总结的 LLM 编码行为准则：编码前先思考、简洁优先、外科手术式改动、目标驱动执行 | 写代码 / 评审 / 重构时自动参考 |
| [`project-init/`](./project-init/) | 自动检测并初始化编程项目，配置 `.claude/` / `.codex/` 目录、CLAUDE.md / AGENTS.md、默认权限、CodeGraph MCP，并维护 `.claude/progress/` 状态追踪 | 启动 Claude Code / Codex、`/loop`、`/goal`，或关键词 `init project` / `初始化项目` / `自主开发` |
| [`web-search/`](./web-search/) | 基于 `curl` 的网络搜索与网页抓取，Google → Bing → Baidu 顺序回退，自动处理反爬 | `/搜索 <关键词> [搜索引擎]` |

## 安装

把整个仓库（或选中的子目录）软链到 `~/.claude/skills/` 即可：

```bash
# 安装全部
git clone https://github.com/zlfyuan/zlf-skills.git
ln -s "$(pwd)/zlf-skills/karpathy-guidelines" ~/.claude/skills/
ln -s "$(pwd)/zlf-skills/project-init"      ~/.claude/skills/
ln -s "$(pwd)/zlf-skills/web-search"       ~/.claude/skills/

# 或者只挑一个
ln -s "$(pwd)/zlf-skills/karpathy-guidelines" ~/.claude/skills/
```

## 贡献

每个技能以独立目录存在，目录内必须有 `SKILL.md`（或 `skill.md`）+ 可选的 `assets/` / `scripts/` / `config.json` / `hooks.json`。

## License

见各技能目录内声明。`karpathy-guidelines` 继承 MIT。
