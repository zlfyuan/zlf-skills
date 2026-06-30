# web-search

> 用 `curl` 做网络搜索和网页抓取 —— 无需浏览器、无需 API key，三大搜索引擎顺序回退。

## 它解决什么问题

LLM 默认不能联网。这个 skill 把"上网"能力以**纯 curl 命令**的形式打包：

- ✅ 不需要付费 API key（Google CSE、Tavily 等都收费）
- ✅ 不需要装浏览器 / Playwright
- ✅ 不需要 Python 运行时
- ✅ Google / Bing / Baidu 自动回退
- ✅ 反爬时自动换 User-Agent

## 触发方式

### 命令触发

```
/搜索 <关键词> [搜索引擎]
```

示例：

```
/搜索 今日新闻
/搜索 python教程 google
/搜索 特斯拉最新消息 bing
/搜索 天气预报 baidu
```

### 关键词触发（自动激活）

中文关键词命中即触发：

- `网络搜索` / `上网` / `网络查询`
- `搜索一下` / `搜一下` / `查一下` / `帮我搜` / `帮我查`
- `看看这个url` / `看看这篇文章` / `查看网页` / `文章`
- `去网上找` / `网上搜`

### URL 自动抓取

**用户消息中出现任何 `http://` 或 `https://` 链接时自动抓取**：

- 匹配正则：`https?://[^\s)<>\"']+`
- 多个 URL 时并行抓取
- 抓取后给出页面标题、关键段落、相关链接

## 搜索策略（fallback 链）

```
Google (默认)  ──失败/质量低──→  Bing  ──失败──→  Baidu
   │                                │               │
   └── 反爬时换 UA ──────────────────┴───────────────┘
```

国内平台（微博 / 知乎 / B 站）走专用接口而非通用搜索。

## 文件结构

```
web-search/
├── README.md      ← 你在这里
├── SKILL.md       ← Claude / Codex 加载的技能定义（含触发规则 + 行为规范）
├── config.json    ← 触发配置：slots / examples / tags（结构化元数据）
├── hooks.json     ← Hook 入口配置（关键词列表 + 自动触发开关）
└── prompt.md      ← 完整的 curl 命令模板 + User-Agent 库（Codex 用）
```

### 各文件的角色

| 文件 | 谁读 | 作用 |
|------|------|------|
| `SKILL.md` | Claude / Codex | 技能定义（frontmatter 描述 + 行为指令） |
| `config.json` | 技能注册器 | 结构化元数据：触发命令、参数槽、示例、分类 |
| `hooks.json` | hook 引擎 | 关键词列表 + 是否自动触发 |
| `prompt.md` | Codex / 高级用法 | 可直接喂给模型的完整 prompt（包含全部 curl 模板） |

## 适用场景

- 📰 实时新闻、热点话题（微博热搜、知乎热榜）
- 📚 百科知识查询
- 🌐 网页内容抓取（任意 URL）
- 📄 技术文档查找
- 🔍 论文 / 博客文章搜索

## 不适用

- ❌ 需要登录的内容（微博私信、知乎收藏等）—— 会失败
- ❌ 大规模爬取 —— 单次搜索/抓取，不是爬虫
- ❌ 需要 JS 渲染的 SPA —— 纯 curl 拿不到动态内容

## 安装

```bash
ln -s "$(pwd)/web-search" ~/.claude/skills/web-search
```

不需要额外配置 —— 装上即用。

## 使用注意

- 所有 curl 命令默认 `--max-time 10` 防止挂起
- 搜索结果需去重 + 过滤，只展示关键信息
- 遵守目标网站的 `robots.txt`
- 反爬时多换几种 User-Agent 重试
- 仅用于合法用途：信息查询、学习研究、知识获取

详见 [`SKILL.md`](./SKILL.md) 的"注意事项"章节。

## 扩展建议

想加新的搜索引擎（如 DuckDuckGo）？

1. 在 [`prompt.md`](./prompt.md) 增加对应的 curl 模板 + UA
2. 更新 [`config.json`](./config.json) 的 `slots` 加新引擎
3. 在 [`SKILL.md`](./SKILL.md) 的 fallback 链中插入
4. 在 [`hooks.json`](./hooks.json) 的关键词列表里加触发词（可选）

## 相关链接

- 父仓库说明：[`../README.md`](../README.md)
- 完整 curl 命令模板：[`prompt.md`](./prompt.md)