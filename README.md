# public

公开脚本与文件，站点地址：<https://pub.gongshuiwen.com>。

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

首次部署需确保当前 Cloudflare 账户可以管理 `gongshuiwen.com`。
更新仓库后重新部署才能更新站点文件。若连接 Workers Builds：
构建命令为 `npm run build`，部署命令为 `cf deploy --prebuilt --mode production`。
