---
name: web-search
description: Web search and page fetching via curl with Google → Bing → Baidu fallback. Use when the user types "/搜索 <关键词>", asks to search the web, look up current information, scrape a page, or check trending topics on Chinese platforms (Weibo, Zhihu, etc.). Also triggers automatically whenever any http:// or https:// URL appears in the conversation — fetch it with curl. Trigger keywords: 网络搜索, 上网, 帮我搜, 帮我查, 查一下, 搜一下, 看看这个url, 文章.
---

# 网络搜索技能 (web-search)

使用 `curl` 命令执行网络搜索和网页内容获取，无需浏览器或 API key。

## 使用方法

```
/搜索 <关键词> [搜索引擎]
```

**搜索引擎优先级**：Google (默认) → Bing → Baidu

示例：

```
/搜索 今日新闻
/搜索 python教程 google
/搜索 特斯拉最新消息 bing
/搜索 天气预报 baidu
```

## 触发关键词

除 `/搜索` 命令外，命中以下任一关键词即自动激活本技能：

- **URL 检测**：用户消息中出现任何 `http://` 或 `https://` 开头的 URL（用户贴的链接、引用、报错信息里的 URL、文档里的 URL 都算）—— 立即用 `curl` 抓取该 URL 的页面内容并解析
  - 匹配正则：`https?://[^\s)<>\"']+`
  - 消息中有多个 URL 时并行抓取，抓取后给出页面标题、关键段落、相关链接
- `网络搜索` / `上网` / `网络查询`
- `搜索一下` / `搜一下` / `查一下` / `帮我搜` / `帮我查`
- `看看这个url` / `看看这篇文章` / `查看网页` / `文章`
- `去网上找` / `网上搜`

## 搜索策略

1. **优先 Google**（搜索质量最高，质量不足或失败时自动切换）
2. **回退 Bing**（国际内容仍可用）
3. **最后 Baidu**（中文内容覆盖最广）
4. 遇到 403 / 反爬时**更换 User-Agent** 重试
5. 国内平台（微博 / 知乎 / B 站）走对应专用接口

完整 curl 命令与 User-Agent 模板见 [`prompt.md`](./prompt.md)。

## 功能特点

- 支持三大搜索引擎：Google、Bing、Baidu
- 自动 Google → Bing → Baidu 顺序回退
- 自动处理反爬机制，使用合适的 User-Agent
- 支持获取任意 URL 的页面内容
- 智能解析搜索结果，提取标题和摘要

## 适用场景

- 实时新闻查询
- 百科知识搜索
- 网页内容抓取
- 热点话题追踪（微博热搜、知乎热榜等）
- 技术文档查找

## 输出格式

```
## 搜索结果：<关键词>

| 排名 | 标题 | 来源 | 摘要 |
|------|------|------|------|
| 1 | xxx | xxx | xxx |
| 2 | xxx | xxx | xxx |

**来源**：Google / Bing / Baidu
**查询时间**：<当前时间>
```

## 注意事项

- 所有 curl 命令必须添加 `--max-time 10` 防止超时
- 搜索结果需去重和过滤，只展示关键信息
- 如果目标网站有反爬机制，多换几种方式尝试
- 对于需要登录的内容（如微博私信），应告知用户无法访问
- 遵守目标网站的 `robots.txt` 规则
- 仅用于合法用途：信息查询、学习研究、知识获取

## 相关文件

- [`prompt.md`](./prompt.md) — 完整 curl 命令与 User-Agent 模板（Codex 兼容）
- [`config.json`](./config.json) — 触发配置与参数定义
- [`hooks.json`](./hooks.json) — Hook 入口配置
