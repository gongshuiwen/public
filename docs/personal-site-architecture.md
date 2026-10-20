# 个人站点与公开资源双站点架构

## 域名与职责

- `gongshuiwen.com`：个人主页、项目、文章、关于页面。
- `www.gongshuiwen.com`：301/308 重定向到 `https://gongshuiwen.com`。
- `pub.gongshuiwen.com`：保持现有公开文件索引、预览、下载和文件直链，避免破坏已有引用。

## 部署边界

- 公开资源：现有 Cloudflare Worker `gongshuiwen-public`，保留 `cloudflare.config.ts` 和当前构建脚本。
- 个人站点：独立 Cloudflare Worker（建议 `gongshuiwen-site`），独立入口、构建命令和生产域名；不应修改公开资源 Worker 的 domains。
- 两套应用可以暂时放在同一个 GitHub 仓库，独立 CI/CD；后续可按需要拆仓。

## 个人站点路线

1. 新增独立 `apps/site` 目录，优先静态生成；页面包含首页、项目、文章、关于。
2. 内容以仓库 Markdown/MDX 为事实来源，不依赖数据库。
3. 支持响应式、深浅色模式、SEO 元信息、sitemap、RSS。
4. 资源页面链接到 `https://pub.gongshuiwen.com`，不复制资源文件。
5. Cloudflare 配置个人站点 Worker、自定义域名和 www 重定向；验证后再上线。

## 上线验收

- `https://gongshuiwen.com` 返回个人站点；
- `https://www.gongshuiwen.com` 跳转至主域名；
- `https://pub.gongshuiwen.com` 仍显示原文件列表；
- `https://pub.gongshuiwen.com/Set-WindowsProxy.ps1` 仍可直接下载；
- 两个站点可独立构建和回滚。

> 本文记录目标架构；Cloudflare DNS、路由和新 Worker 的实际上线状态须单独验证。
