# 个人站点

独立部署至 `gongshuiwen.com` 的静态技术主页，仅公开联系邮箱 `gongshuiwen@gmail.com`，不展示其他个人身份资料或联系方式。

## 本地运行

```sh
cd apps/site
npm install
npm run dev
```

## 构建与部署

```sh
cd apps/site
npm install
npm run build
npm run deploy
```

Cloudflare Workers Builds 配置：根目录 `apps/site`，构建命令 `npm run build`，部署命令 `npm run deploy`；与仓库根目录的公开资源 Worker 独立部署。首次部署前检查域名路由、账号权限及实际构建产物。

`www.gongshuiwen.com` 到主域名的重定向需在 Cloudflare 配置。
