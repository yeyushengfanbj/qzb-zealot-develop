# Windows 服务器发布指南（Docker 部署）

本文用于在 Windows 11 / Windows Server 上发布 Zealyn（镜像来自 GHCR）。

适用场景：
- 你在 Mac 上开发并推送代码
- 你希望在 Windows 机器（物理机或 Parallels 虚拟机）上作为运行服务器
- 通过 Docker Compose 启动服务

---

## 0. Parallels Windows 11 快速发布清单（10 分钟）

如果你现在就要在 Parallels 的 Windows 11 里发布，按下面顺序执行即可。

### 0.1 在 Mac 开发机执行

1. 推送最新代码：

```bash
git add -A
git commit -m "release: deploy to windows"
git push origin main
```

2. 拿到 12 位 SHA：

```bash
git rev-parse --short=12 HEAD
```

记下结果，例如：`93dcf33b5e72`。

### 0.2 在 Windows 11 虚拟机执行

1. 安装并启动 Docker Desktop（首次需要）
2. 打开 PowerShell，登录 GHCR：

```powershell
docker login ghcr.io -u yeyushengfanbj
```

3. 进入部署目录：

```powershell
cd C:\zealyn-deploy
```

4. 把 `.env` 与 `.env.local` 的 `ZEALOT_IMAGE` 改成：

```text
ghcr.io/yeyushengfanbj/qzb-zealot-develop:sha-93dcf33b5e72
```

把上面的 SHA 换成你自己的 12 位 SHA。

5. 执行发布：

```powershell
docker compose -f docker-compose.local.yml pull zealyn
docker compose -f docker-compose.local.yml up -d --force-recreate zealyn
```

6. 验证是否成功：

```powershell
docker compose -f docker-compose.local.yml ps
curl.exe -i http://localhost:8080/api/health
```

状态为 Up 且 health 返回 200，即发布完成。

### 0.3 发布失败时快速回滚

1. 把 `ZEALOT_IMAGE` 改回上一个稳定标签
2. 重新执行：

```powershell
docker compose -f docker-compose.local.yml pull zealyn
docker compose -f docker-compose.local.yml up -d --force-recreate zealyn
```

3. 再次检查：

```powershell
curl.exe -i http://localhost:8080/api/health
```

### 0.4 客户方服务器参数替换（可直接套用）

先把下面占位符替换成客户环境参数，再执行后续章节命令。

推荐做法：
1. 复制 `customer.release.env.example` 为 `customer.release.env`
2. 只改 `customer.release.env` 一份参数
3. 用 `bin/windows-deploy.ps1` 一键发布

参数占位符清单：
- `<CLIENT_SERVER_NAME>`：客户服务器名称（示例：`prod-win-01`）
- `<CLIENT_SERVER_IP>`：客户服务器 IP（示例：`10.10.20.35`）
- `<CLIENT_SERVER_PORT>`：客户服务端口（示例：`8080`）
- `<CLIENT_DEPLOY_DIR>`：客户部署目录（示例：`C:\zealyn-deploy`）
- `<CLIENT_DOMAIN>`：客户域名（示例：`ci.customer.com`）
- `<CLIENT_HEALTH_PATH>`：健康检查路径（默认：`/api/health`）
- `<GHCR_USER>`：GHCR 用户名（示例：`yeyushengfanbj`）
- `<GHCR_PAT>`：GHCR 访问令牌（PAT）
- `<IMAGE_REPO>`：镜像仓库（示例：`ghcr.io/yeyushengfanbj/qzb-zealot-develop`）
- `<IMAGE_TAG>`：镜像标签（示例：`sha-93dcf33b5e72`）
- `<ROLLBACK_IMAGE_TAG>`：回滚镜像标签（示例：`sha-a4cddbc63fa6`）
- `<API_BASE_URL>`：对外 API 基础地址（示例：`https://ci.customer.com`）

建议把以下模板保存为客户发布参数（仅示例）：

```text
CLIENT_SERVER_NAME=prod-win-01
CLIENT_SERVER_IP=10.10.20.35
CLIENT_SERVER_PORT=8080
CLIENT_DEPLOY_DIR=C:\zealyn-deploy
CLIENT_DOMAIN=ci.customer.com
CLIENT_HEALTH_PATH=/api/health
GHCR_USER=yeyushengfanbj
IMAGE_REPO=ghcr.io/yeyushengfanbj/qzb-zealot-develop
IMAGE_TAG=sha-93dcf33b5e72
ROLLBACK_IMAGE_TAG=sha-a4cddbc63fa6
API_BASE_URL=https://ci.customer.com
```

如果你使用模板文件方式：

```powershell
Copy-Item customer.release.env.example customer.release.env
notepad customer.release.env
```

---

## 0B. 客户方服务器发布（参数化模板）

本节用于“客户方 Windows 服务器”发布。你只要把占位符替换掉即可执行。

### 0B.1 在客户服务器上登录 GHCR

```powershell
docker login ghcr.io -u <GHCR_USER>
```

输入 `<GHCR_PAT>` 完成登录。

如果你使用一键脚本，`GHCR_PAT` 可写在 `customer.release.env`，脚本会自动登录。

### 0B.2 更新客户服务器环境变量文件

编辑 `<CLIENT_DEPLOY_DIR>\\.env` 与 `<CLIENT_DEPLOY_DIR>\\.env.local`：

```text
ZEALOT_IMAGE=<IMAGE_REPO>:<IMAGE_TAG>
```

如果客户环境要求指定外部访问地址，建议在 `.env.local` 中同步业务地址相关变量（按你项目实际变量名填写）：

```text
ZEALOT_DOMAIN=<CLIENT_DOMAIN>
ZEALOT_HOST=<CLIENT_SERVER_IP>
ZEALOT_PORT=<CLIENT_SERVER_PORT>
API_BASE_URL=<API_BASE_URL>
```

### 0B.3 执行发布

```powershell
cd <CLIENT_DEPLOY_DIR>
docker compose -f docker-compose.local.yml pull zealyn
docker compose -f docker-compose.local.yml up -d --force-recreate zealyn
```

### 0B.4 验证发布

本机回环检查：

```powershell
curl.exe -i http://localhost:<CLIENT_SERVER_PORT><CLIENT_HEALTH_PATH>
```

客户地址检查：

```powershell
curl.exe -i http://<CLIENT_SERVER_IP>:<CLIENT_SERVER_PORT><CLIENT_HEALTH_PATH>
```

若配置了域名和 HTTPS，请再检查：

```powershell
curl.exe -i https://<CLIENT_DOMAIN><CLIENT_HEALTH_PATH>
```

### 0B.5 回滚模板

把 `<IMAGE_TAG>` 改成上一个稳定版本后执行：

```powershell
cd <CLIENT_DEPLOY_DIR>
docker compose -f docker-compose.local.yml pull zealyn
docker compose -f docker-compose.local.yml up -d --force-recreate zealyn
curl.exe -i http://localhost:<CLIENT_SERVER_PORT><CLIENT_HEALTH_PATH>
```

一键回滚脚本（推荐）：

```powershell
cd <你的仓库目录>
powershell -ExecutionPolicy Bypass -File .\bin\windows-rollback.ps1 -ConfigPath .\customer.release.env
```

如果你希望临时回滚到指定标签，也可以直接传参覆盖：

```powershell
powershell -ExecutionPolicy Bypass -File .\bin\windows-rollback.ps1 -ConfigPath .\customer.release.env -RollbackTag sha-a4cddbc63fa6
```

### 0B.6 你可直接替换的接口地址模板

常用接口模板（替换后可发给客户联调）：

- 健康检查：`https://<CLIENT_DOMAIN><CLIENT_HEALTH_PATH>`
- 应用主页：`https://<CLIENT_DOMAIN>/`
- API 基础地址：`<API_BASE_URL>`
- 若仅内网可访问：`http://<CLIENT_SERVER_IP>:<CLIENT_SERVER_PORT>`

### 0B.7 一键发布（推荐）

本仓库提供了 Windows PowerShell 脚本：`bin/windows-deploy.ps1`。

执行步骤：

1. 在客户服务器保存参数文件（例如 `C:\zealyn-deploy\customer.release.env`）
2. 打开 PowerShell 执行：

```powershell
cd <你的仓库目录>
powershell -ExecutionPolicy Bypass -File .\bin\windows-deploy.ps1 -ConfigPath .\customer.release.env
```

可选参数：

```powershell
# 如果已提前 docker login，可跳过登录步骤
powershell -ExecutionPolicy Bypass -File .\bin\windows-deploy.ps1 -ConfigPath .\customer.release.env -SkipLogin
```

脚本会自动完成：
1. 读取参数文件
2. 更新 `<CLIENT_DEPLOY_DIR>\\.env` 和 `.env.local` 的 `ZEALOT_IMAGE`
3. 按需更新 `.env.local` 的 `ZEALOT_DOMAIN / ZEALOT_HOST / ZEALOT_PORT / API_BASE_URL`
4. 执行 `docker compose pull` + `up -d --force-recreate`
5. 执行健康检查

对应回滚脚本：`bin/windows-rollback.ps1`

回滚脚本会自动完成：
1. 读取 `ROLLBACK_IMAGE_TAG`（或 `-RollbackTag`）
2. 更新部署目录 `.env` 与 `.env.local` 的 `ZEALOT_IMAGE`
3. 执行 `docker compose pull` + `up -d --force-recreate`
4. 执行健康检查

---

## 1. 发布架构说明

发布流程：
1. 在代码仓库推送代码（`git push origin main`）
2. GitHub Actions 构建镜像并推送到 GHCR
3. 在 Windows 服务器拉取指定标签镜像
4. 用 Compose 重建 `zealyn` 服务
5. 健康检查通过后发布完成

镜像格式：
- `ghcr.io/yeyushengfanbj/qzb-zealot-develop:sha-<12位提交SHA>`

示例：
- `ghcr.io/yeyushengfanbj/qzb-zealot-develop:sha-93dcf33b5e72`

---

## 2. 前置条件

在 Windows 服务器上需要具备：

1. Windows 11 或 Windows Server（建议 Windows 11 + WSL2）
2. 管理员权限
3. 稳定网络（可访问 `ghcr.io`）
4. 已安装 Git（可选，但建议）
5. Docker Desktop（Windows 11 推荐）或 Docker Engine（Windows Server）

仓库内需准备以下文件（从 Mac 拷贝到 Windows 部署目录）：
1. `docker-compose.local.yml`
2. `.env`
3. `.env.local`
4. （可选）`.release-last-image`（用于人工记录回滚状态）

---

## 3. 在 Windows 安装 Docker（推荐 Docker Desktop）

### 3.1 安装 WSL2（Windows 11）

以管理员打开 PowerShell，执行：

```powershell
wsl --install
```

完成后重启系统。

检查版本：

```powershell
wsl --status
```

### 3.2 安装 Docker Desktop

1. 打开：https://www.docker.com/products/docker-desktop/
2. 下载 Windows 版本并安装
3. 安装时启用 WSL2 后端（Use WSL 2 instead of Hyper-V）
4. 安装结束后启动 Docker Desktop

验证 Docker：

```powershell
docker version
docker compose version
```

如果能输出版本号，说明安装成功。

---

## 4. 登录 GHCR

你需要 GitHub Personal Access Token（PAT），至少包含：
- `read:packages`
- 如果仓库私有，建议额外给 `repo`

在 PowerShell 执行：

```powershell
docker login ghcr.io -u yeyushengfanbj
```

按提示输入 PAT（不会回显）。

登录成功会看到：
- `Login Succeeded`

---

## 5. 准备部署目录

建议在 Windows 建立固定目录，例如：

```powershell
mkdir C:\zealyn-deploy
```

把以下文件放入 `C:\zealyn-deploy`：
1. `docker-compose.local.yml`
2. `.env`
3. `.env.local`

进入目录：

```powershell
cd C:\zealyn-deploy
```

---

## 6. 首次发布（手动）

### 6.1 获取要发布的镜像标签

在你的开发机（Mac）获取 12 位提交 SHA：

```bash
git rev-parse --short=12 HEAD
```

得到例如 `93dcf33b5e72`，则发布标签是：
- `sha-93dcf33b5e72`

完整镜像：
- `ghcr.io/yeyushengfanbj/qzb-zealot-develop:sha-93dcf33b5e72`

### 6.2 更新 Windows 上环境文件

编辑 `C:\zealyn-deploy\.env` 与 `C:\zealyn-deploy\.env.local`，确认：

```text
ZEALOT_IMAGE=ghcr.io/yeyushengfanbj/qzb-zealot-develop:sha-93dcf33b5e72
```

### 6.3 拉取并启动

```powershell
docker compose -f docker-compose.local.yml pull zealyn
docker compose -f docker-compose.local.yml up -d --force-recreate zealyn
```

### 6.4 验证发布

查看容器状态：

```powershell
docker compose -f docker-compose.local.yml ps
```

查看最近日志：

```powershell
docker compose -f docker-compose.local.yml logs --tail=100 zealyn
```

健康检查（如果映射 8080 端口）：

```powershell
curl.exe -i http://localhost:8080/api/health
```

返回 `200` 代表服务正常。

---

## 7. 日常发布流程（推荐）

每次发布按以下步骤执行：

1. 在开发机推送代码：

```bash
git add -A
git commit -m "feat: your change"
git push origin main
```

2. 等待 GitHub Actions 完成镜像构建
3. 获取本次提交 12 位 SHA
4. 在 Windows 服务器更新 `.env` / `.env.local` 的 `ZEALOT_IMAGE`
5. 执行：

```powershell
docker compose -f docker-compose.local.yml pull zealyn
docker compose -f docker-compose.local.yml up -d --force-recreate zealyn
```

6. 做健康检查和日志确认

---

## 8. 回滚流程

当发布后异常，可回滚到上一个稳定镜像。

### 8.1 明确回滚镜像

你需要一个已知可用镜像，例如：
- `ghcr.io/yeyushengfanbj/qzb-zealot-develop:sha-a4cddbc63fa6`

### 8.2 更新配置并重建

修改 `ZEALOT_IMAGE` 为回滚镜像后执行：

```powershell
docker compose -f docker-compose.local.yml pull zealyn
docker compose -f docker-compose.local.yml up -d --force-recreate zealyn
```

### 8.3 验证回滚

```powershell
docker compose -f docker-compose.local.yml ps
curl.exe -i http://localhost:8080/api/health
```

---

## 9. 常见故障排查

### 9.1 `manifest unknown`

原因：目标标签镜像尚未推送成功（Actions 仍在构建或失败）。

处理：
1. 到 GitHub Actions 确认 workflow 成功
2. 核对 SHA 与标签是否一致
3. 重新执行 `pull`

### 9.2 `unauthorized` 或拉取失败

原因：未登录 GHCR 或 token 权限不足。

处理：
1. 重新登录：`docker login ghcr.io -u yeyushengfanbj`
2. 检查 PAT 权限（至少 `read:packages`）

### 9.3 容器启动后 502 / 健康检查失败

原因：应用冷启动中、数据库未就绪、配置错误。

处理：
1. 先等 15-30 秒再查健康
2. 看日志：`docker compose -f docker-compose.local.yml logs --tail=200 zealyn`
3. 检查 `.env.local` 数据库与密钥配置

### 9.4 端口被占用

处理：
1. 检查占用进程
2. 修改映射端口（在 `docker-compose.local.yml`）
3. 重新 `up -d --force-recreate`

---

## 10. 运维建议

1. 固定发布规范：只发布 `sha-<12位SHA>` 标签
2. 每次发布记录：发布时间、镜像 tag、结果
3. 保留最近 3 个稳定镜像 tag 便于回滚
4. 定期清理无用镜像：

```powershell
docker image prune -f
```

5. 发布后做最小验证：
- 健康检查接口
- 登录页面可访问
- 核心上传/下载链路可用

---

## 11. 可选：自动化发布（进阶）

如果你希望“push main 后 Windows 自动部署”，可在 Windows 上安装 GitHub Actions self-hosted runner，并在 workflow 增加 deploy job（运行 `docker compose pull/up`）。

这会把手工发布变成一键自动发布，但建议先把本文档的手动流程跑通再自动化。
