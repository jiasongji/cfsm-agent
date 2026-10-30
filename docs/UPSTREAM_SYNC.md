# 上游同步 SOP（人工审查制）

适用：`huilang-me/cfsm-agent`（探针上游）与 `huilang-me/CF-Server-Monitor`（服务端上游）。
原则：**上游一切变更先审查后合并**，fork 的自动同步 workflow 已删除，永不再开。

## 触发时机
- 上游发新 release（留意 huilang-me 的 Release 页与 tag）；
- 或收到上游重要修复/安全公告时主动同步。

## 流程（两个仓库通用）

```bash
git fetch upstream
git log --oneline main..upstream/main          # 看新增提交
git diff main...upstream/main --stat            # 看涉及文件
git diff main...upstream/main                   # 逐个文件审 diff
```

### 审查重点
1. **更新通道**：`update.go` 的 defaultUpdateRepo、release API、下载/校验逻辑——任何改动都要确认仍指向 `jiasongji/cfsm-agent` 且 checksums 校验未被削弱；
2. **配置下发**：`agent.go` 远程配置白名单、`agentConfig.js`——防止新增未审查的远程控制能力；
3. **脚本注入面**：install.sh / install.ps1 / entrypoint.sh 的下载源、命令拼接、校验逻辑；
4. **新依赖**：go.mod / package.json 新增项——评估必要性；
5. **服务端安全**：auth、CORS、CSP、公开 API 面。

### 合并与验证
```bash
git merge upstream/main          # 或 upstream/dev（上游 dev 含未发版修复时）
```
- 探针：`go build ./... && go vet ./... && go test ./...` 全绿后，**升 patch 版本发版**（v1.2.0 → v1.2.1，版本号永不复用、不重写已发布 release）。已开自动更新的主机 6 小时内自动升级；
- 服务端：`npm test`（162 例，唯一允许失败的是本机 mkcert 环境）+ `npm run build:frontend`，push 后手动 `gh workflow run deploy.yml --ref main -R jiasongji/CF-Monitor` 部署并线上验证。

### 合并冲突保留清单（冲突时一律保我方版本）
- 探针：update.go 更新源常量、install.sh/ps1 的 REPO、checksums 校验、DNS 轮转/共享客户端修复；
- 服务端：admin/index.vue 安装命令 URL、version.js、locale installVersionTip、我方全部安全修复（CSP 转义、CORS 白名单、健康检查鉴权、主题降级）。

### 发版后验收
- release assets 齐全（20 平台 + checksums.txt）；
- 抽查 sha256 一致、`strings` 确认 defaultUpdateRepo 仍为 jiasongji；
- 面板观察 6 小时内舰队自动升级情况。

## 记录
每次同步在主目录 `AUDIT-*.md` 追加一节：同步了哪些上游提交、审查结论、发版/部署号。
