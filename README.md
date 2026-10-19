# public

公开脚本与文件，站点地址：<https://pub.gongshuiwen.com>。

## 在线预览

点击文件列表中的文件名或“预览”，可在线阅读脚本、Markdown、文本及常见配置文件。
预览页提供行号定位、复制全文、自动换行和原文件下载；文件内容按纯文本显示。
支持 UTF-8 和带 BOM 的 UTF-16 文本，超过 1 MiB 或无法识别的文件仅提供下载。
生成的预览页使用 `preview/` 路径，界面资源使用 `site-assets/` 路径，请勿将公开文件放入这两个目录。

## Windows 代理脚本

下载脚本后，在 PowerShell 7 中运行：

```powershell
Invoke-WebRequest 'https://pub.gongshuiwen.com/Set-WindowsProxy.ps1' -OutFile Set-WindowsProxy.ps1

# 默认代理 127.0.0.1:10808
.\Set-WindowsProxy.ps1

# 自定义代理
.\Set-WindowsProxy.ps1 -ProxyAddress '192.168.1.10:7890'

# 关闭手动代理、PAC 和自动检测，并清除代理环境变量
.\Set-WindowsProxy.ps1 -Disable
```

## 站点维护

使用 Cloudflare Workers 托管静态文件，配置文件为 `cloudflare.config.ts`。
仓库中的公开内容保留原有访问路径；构建、依赖和隐藏文件不发布。

```shell
npm ci
npm run build
cf auth login
cf deploy --prebuilt --mode production
```

## 自动发布

Cloudflare Workers Builds 连接本仓库，`main` 分支更新后自动构建并发布到
<https://pub.gongshuiwen.com>。其他分支不触发生产发布。

- Worker：`gongshuiwen-public`
- 生产分支：`main`
- 项目根目录：`/`
- Node.js：`24.14.1`
- 构建命令：`npm run build`
- 部署命令：`npx cf deploy --prebuilt --mode production`

首次关联时，需要在 GitHub 中为 `Cloudflare Workers and Pages` 应用授权本仓库。
之后推送 `main` 即可发布，无需在本机执行部署命令。

构建凭据保存在 Cloudflare，仓库不保存密钥。
可在 Cloudflare 控制台中进入该 Worker 的 Builds 页面查看构建和部署日志。
上面的命令仍可用于本地手动部署。
