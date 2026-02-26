# CloudflareSpeedTest-docker 仓库修改说明

> [!WARNING]
> ⚠️ **本仓库中的所有代码修改均由 AI 完成。**
> ⚠️ **上述修改仅供参考与实验使用，不对正确性、稳定性、安全性、适用性作任何明示或暗示保证。**
> ⚠️ **使用者需自行审查、测试并承担由此产生的全部风险与责任。**

本文档用于说明本仓库相对上游项目的改动内容、变更记录与使用方式。

## 1. 修改部分概览

本仓库在保持 `CloudflareSpeedTest` 核心测速能力的前提下，增加了 Docker 化能力与 CI 自动构建发布能力，主要包括：

- Docker 多架构构建（以 Alpine 支持架构为主）
- GitHub Actions 自动构建并推送 GHCR 镜像
- 容器元数据（OCI Labels）补充
- 基于 `.env` 的 Gist 上传功能（可选）

## 2. 变更记录

### 2026-02-26

- 新增 GitHub Actions 工作流：`.github/workflows/docker-ci.yml`
  - 自动构建并推送 GHCR 镜像（Push 为预发布标签，Release 为正式标签）
  - 多架构构建平台（Alpine 支持优先）：
    - `linux/amd64`
    - `linux/arm64`
    - `linux/arm/v6`
    - `linux/arm/v7`
    - `linux/386`
- 新增 GitHub Actions 工作流：`.github/workflows/release-binaries.yml`
  - 在 GitHub Release 发布时自动编译多平台二进制并上传到 Release Assets
  - 二进制打包平台：
    - `linux/amd64`
    - `linux/arm64`
    - `linux/386`
    - `linux/armv6`
    - `linux/armv7`
    - `windows/amd64`
    - `windows/386`
    - `darwin/amd64`
    - `darwin/arm64`
  - 同步生成 `checksums.txt`（SHA256）
  - 使用 GPG 对 `checksums.txt` 进行签名，生成 `checksums.txt.sig` 与 `checksums.txt.asc`
- 更新 `Dockerfile`
  - 支持按目标平台动态交叉编译（`TARGETARCH/TARGETVARIANT`）
  - 增加 OCI 元数据标签（title/description/source/documentation/licenses）
  - 增加 `curl` 与 `jq`，用于 Gist API 上传
  - 使用 `docker-entrypoint.sh` 作为容器入口
- 新增 `docker-entrypoint.sh`
  - 先执行 `cfst`
  - 成功后可按 `.env` 配置将 `result.csv` 上传到 GitHub Gist
- 新增 `.env.example`
  - 提供 Gist 上传相关环境变量模板
- 更新 `.gitignore`
  - 忽略 `.env`，防止密钥误提交

## 3. 用法

## 3.0 镜像标签策略

- `master` 分支 Push：发布预发布标签（如 `x.y.z-pre.N`）与通道标签 `pre`
- GitHub Release（published）：发布正式版本标签（如 `x.y.z`）并更新 `latest`

如需跟进日常 CI 构建结果，请使用 `:pre`；如需稳定版本，请使用 `:latest` 或具体版本标签。

## 3.0.1 二进制资产发布策略

- 触发方式：GitHub Release（`published`）
- 资产命名：`cfst_<os>_<arch>[v6|v7].tar.gz|zip`
  - 示例：`cfst_linux_amd64.tar.gz`、`cfst_linux_armv7.tar.gz`、`cfst_windows_amd64.zip`
- 每次发布会附带 `checksums.txt` 用于完整性校验
- 每次发布会附带 `checksums.txt.sig` 与 `checksums.txt.asc`，用于校验签名真实性

## 3.0.2 GPG 签名配置

在仓库 `Settings -> Secrets and variables -> Actions` 中配置：

- `GPG_PRIVATE_KEY`
  - ASCII-armored 私钥全文（`-----BEGIN PGP PRIVATE KEY BLOCK-----` 到结尾）
- `GPG_PASSPHRASE`
  - 对应私钥口令

发布时工作流会导入该私钥并对 `checksums.txt` 做 detached signature。

## 3.1 基础测速（不上传 Gist）

```bash
docker run --rm ghcr.io/bigzhangbig/cloudflarespeedtest-docker:latest -n 200
podman run --rm ghcr.io/bigzhangbig/cloudflarespeedtest-docker:latest -n 200
```

使用 Compose 时（Docker Compose / Podman Compose）：

```yaml
# compose.yml
services:
  cfst:
    image: ghcr.io/bigzhangbig/cloudflarespeedtest-docker:latest
```

```bash
docker compose run --rm cfst -n 200
podman compose run --rm cfst -n 200
```

Compose 传参推荐写法：

```bash
# 临时传参（每次命令可不同）
docker compose run --rm cfst -- -n 200 -url https://cfspeedtest.freenode.indevs.in/5G
podman compose run --rm cfst -- -n 200 -url https://cfspeedtest.freenode.indevs.in/5G
```

```yaml
# 固定参数（写入 compose.yml）
services:
  cfst:
    image: ghcr.io/bigzhangbig/cloudflarespeedtest-docker:latest
    command: ["-n", "200", "-url", "https://cfspeedtest.freenode.indevs.in/5G"]
```

```bash
docker compose up --abort-on-container-exit
podman compose up
```

## 3.2 启用 Gist 自动上传

### 步骤 1：准备环境变量

```bash
cp .env.example .env
```

编辑 `.env`，至少设置：

```dotenv
GIST_TOKEN=你的GitHubToken
GIST_ID=你的GistID
```

> Token 需要具备 Gist 写入权限（`gist` scope 或等效细粒度权限）。

### 步骤 2：运行容器

```bash
docker run --rm --env-file .env ghcr.io/bigzhangbig/cloudflarespeedtest-docker:latest -n 200
podman run --rm --env-file .env ghcr.io/bigzhangbig/cloudflarespeedtest-docker:latest -n 200
```

使用 Compose 时（Docker Compose / Podman Compose）：

```yaml
# compose.yml
services:
  cfst:
    image: ghcr.io/bigzhangbig/cloudflarespeedtest-docker:latest
    env_file:
      - .env
```

```bash
docker compose run --rm cfst -n 200
podman compose run --rm cfst -n 200
```

若需通过 Compose 临时传参（覆盖默认命令）：

```bash
docker compose run --rm cfst -- -n 200 -url https://cfspeedtest.freenode.indevs.in/5G
podman compose run --rm cfst -- -n 200 -url https://cfspeedtest.freenode.indevs.in/5G
```

测速成功后会上传结果文件，并在日志中输出 Gist 链接。

默认行为：每次上传会覆盖同一个 Gist 文件内容，并清理该 Gist 中其他旧文件。

## 3.3 常用环境变量说明

- `GIST_TOKEN`
  - GitHub Token（推荐使用）
- `GIST_ID`
  - 目标 Gist ID；仅当 `GIST_TOKEN` 与 `GIST_ID` 同时存在时才会上传
- `GIST_FILENAME`
  - 上传到 Gist 的文件名，默认 `result.csv`
- `GIST_DESCRIPTION`
  - Gist 描述信息；为空时默认 `UTC+8` 时间戳
- `GIST_RESULT_FILE`
  - 上传文件路径，默认 `result.csv`

## 3.4 版本号同步说明

- CI 镜像构建时，会自动读取上游 `XIU2/CloudflareSpeedTest` 最新 Release Tag，并注入到容器内程序版本。
- 因此发布到 GHCR 的镜像内版本会与上游发布版本同步（例如 `v2.3.4`）。
- 本地手动构建若不传 `VERSION`，会使用默认值 `v0.0.0`。
- 本地若要同步上游版本，请在构建时显式传入：

```bash
podman build --build-arg VERSION=v2.3.4 -t cfst-app .
```

## 4. 说明

- 本仓库主要维护 Docker / CI / 发布相关能力。
- 上游测速逻辑以 `XIU2/CloudflareSpeedTest` 为准。
