# 发布指南（本地 Docker 部署）

本文给出两种发布方式：

- 方式 A：自动脚本发布（推荐）
- 方式 B：手动发布（可控性更高）

## 前置条件

- 代码已推送到远端分支（通常是 `main`）
- GitHub Actions 工作流 `Publish Custom GHCR Image` 已完成且成功
- 本地可访问 GHCR（如有网络限制，请先配置代理）

## 方式 A：自动脚本发布（推荐）

### 1. 触发镜像构建

```bash
git add -A
git commit -m "feat: your change"
git push origin main
```

### 2. 获取本次提交的 12 位 SHA

```bash
git rev-parse --short=12 HEAD
```

示例输出：

```text
93dcf33b5e72
```

对应镜像标签就是：`sha-93dcf33b5e72`

### 3. 确认镜像已可用（可选但推荐）

```bash
docker manifest inspect ghcr.io/yeyushengfanbj/qzb-zealot-develop:sha-93dcf33b5e72 >/dev/null && echo ready || echo building
```

### 4. 执行自动发布脚本

```bash
bin/release-deploy sha-93dcf33b5e72
```

也可以直接传 12 位 SHA（脚本会自动补 `sha-` 前缀）：

```bash
bin/release-deploy 93dcf33b5e72
```

### 5. 自动脚本会做什么

- 校验目标镜像存在
- 记录当前镜像到 `.release-last-image`（用于回滚）
- 更新 `.env` 与 `.env.local` 的 `ZEALOT_IMAGE`
- 执行 `docker compose pull` + `up -d --force-recreate`
- 自动健康检查 `http://localhost:8080/api/health`

### 6. 脚本方式回滚

回滚到上一个版本：

```bash
bin/release-rollback
```

指定镜像回滚：

```bash
bin/release-rollback ghcr.io/yeyushengfanbj/qzb-zealot-develop:sha-a4cddbc63fa6
```

## 方式 B：手动发布

### 1. 触发镜像构建

```bash
git add -A
git commit -m "feat: your change"
git push origin main
```

### 2. 取当前提交的 12 位 SHA

```bash
SHA12=$(git rev-parse --short=12 HEAD)
echo "$SHA12"
```

### 3. 确认 GHCR 镜像可用

```bash
docker manifest inspect ghcr.io/yeyushengfanbj/qzb-zealot-develop:sha-$SHA12 >/dev/null
```

### 4. 更新部署镜像

编辑 `.env`：

```text
ZEALOT_IMAGE=ghcr.io/yeyushengfanbj/qzb-zealot-develop:sha-<你的12位SHA>
```

编辑 `.env.local`：

```text
ZEALOT_IMAGE=ghcr.io/yeyushengfanbj/qzb-zealot-develop:sha-<你的12位SHA>
```

### 5. 重建服务

```bash
docker compose -f docker-compose.local.yml pull zealyn
docker compose -f docker-compose.local.yml up -d --force-recreate zealyn
```

### 6. 发布后验证

```bash
curl -si --max-time 20 http://localhost:8080/api/health | head -12
docker compose -f docker-compose.local.yml ps
grep '^ZEALOT_IMAGE=' .env .env.local
```

## 常见问题

### Q1：`manifest unknown` 是什么？

镜像还没构建完。请等待 Actions 成功后再部署。

### Q2：`ZEALOT_IMAGE: command not found` 是什么？

你把变量名当命令执行了。请用下面方式查看：

```bash
grep '^ZEALOT_IMAGE=' .env .env.local
```

### Q3：构建慢怎么办？

优先优化 `publish_custom_ghcr.yml`：

- 限定触发分支
- 增加缓存（`cache-from/cache-to: type=gha`）
- 非必须时只构建单架构

## 慢网发布模式（推荐）

如果服务器网络较慢，建议使用“本地已有镜像 + 跳过拉取”模式。

### Linux/macOS 服务器

先把镜像预热到服务器本地（仅首次或版本变更时）：

```bash
docker pull ghcr.io/yeyushengfanbj/qzb-zealot-develop:sha-<12位SHA>
```

发布时跳过拉取：

```bash
RELEASE_SKIP_PULL=1 bin/release-deploy sha-<12位SHA>
```

### Windows 服务器

若已提前 `docker pull` 或 `docker load` 到本机，发布时可跳过拉取：

```powershell
powershell -ExecutionPolicy Bypass -File .\bin\windows-deploy.ps1 -ConfigPath .\customer.release.env -SkipPull
```

### 离线/弱网补充（Windows 虚拟机特别有效）

如果你在 Mac 开发机网络更好，可在 Mac 拉镜像后导出，复制到 Windows 再导入：

```bash
docker pull ghcr.io/yeyushengfanbj/qzb-zealot-develop:sha-<12位SHA>
docker save ghcr.io/yeyushengfanbj/qzb-zealot-develop:sha-<12位SHA> -o zealyn-image.tar
```

Windows 导入：

```powershell
docker load -i .\zealyn-image.tar
```

然后执行 `-SkipPull` 发布。
