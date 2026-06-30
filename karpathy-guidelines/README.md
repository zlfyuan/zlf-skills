# karpathy-guidelines

> 来自 [Andrej Karpathy](https://x.com/karpathy/status/2015883857489522876) 的 LLM 编码行为准则 —— 给 Claude / Codex 当参考纪律用的纯文本 skill。

## 它是什么

不是工具，是一个**行为约束 skill**：当 Claude / Codex 写代码、评审、重构时，自动加载 [`SKILL.md`](./SKILL.md) 作为额外的判断准则。目的是对抗 LLM 编码的常见毛病：

- 跳过思考、直接动手
- 过度抽象、堆"灵活性"
- 顺手"改进"无关代码
- 目标模糊、不知道何时停

## 四条准则（详见 [SKILL.md](./SKILL.md)）

| # | 准则 | 一句话 |
|---|------|--------|
| 1 | **Think Before Coding** | 不假设，不藏困惑，把 tradeoff 摆出来 |
| 2 | **Simplicity First** | 解决问题所需的最少代码，不写投机性功能 |
| 3 | **Surgical Changes** | 只动必须动的代码，连自己引入的孤儿也要清掉 |
| 4 | **Goal-Driven Execution** | 把任务转成可验证的成功标准，循环到通过 |

**取舍**：这些准则偏向谨慎而非速度。对琐碎任务要靠判断 —— 别把 5 行的 typo 修复当成架构评审。

## 适用场景

✅ 适合：
- 写新功能 / 加新模块
- 重构现有代码
- Code review / PR 检查
- 排查 bug

⚠️ 不适合（或要克制）：
- 一行 typo 修复
- 纯文档 / 注释更新
- 解释概念 / 回答问题

## 安装

```bash
# 软链到 Claude Code skills 目录
ln -s "$(pwd)/karpathy-guidelines" ~/.claude/skills/karpathy-guidelines

# Codex 路径类似
ln -s "$(pwd)/karpathy-guidelines" ~/.codex/skills/karpathy-guidelines
```

不需要任何外部依赖 —— 整个 skill 就一个 `SKILL.md` 文件。

## 文件结构

```
karpathy-guidelines/
├── README.md   ← 你在这里
└── SKILL.md    ← Claude / Codex 实际加载的技能定义（含 frontmatter + 4 条准则）
```

## 配合其他 skill

- [`../project-init/`](../project-init/)：初始化项目时，CLAUDE.md 里可引用这 4 条准则作为团队编码纪律
- 任何需要写代码的 skill：搭配使用，让 LLM 写代码时自动收敛

## 来源与许可

- 原始观察：[Andrej Karpathy on X](https://x.com/karpathy/status/2015883857489522876)
- License: MIT（继承自原帖公开引用）