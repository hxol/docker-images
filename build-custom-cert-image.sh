#!/bin/bash

# --- 配置 ---
# ... (前面的 PAT 和 GITHUB_USERNAME 输入部分保持不变) ...

unset SCRIPT_CR_PAT
read -sp '请输入您的 GitHub Personal Access Token (需要 repo 和 write:packages 权限): ' SCRIPT_CR_PAT
echo

if [ -z "$SCRIPT_CR_PAT" ]; then
    echo "错误：未输入 PAT。"
    exit 1
fi

unset GITHUB_USERNAME
read -p '请输入您的 GitHub 用户名: ' GITHUB_USERNAME
echo

if [ -z "$GITHUB_USERNAME" ]; then
    echo "错误：未输入 GitHub 用户名。"
    exit 1
fi

# 新增：询问用于关联的公共仓库名称
unset PUBLIC_REPO_NAME
read -p '请输入您希望关联此镜像的 GitHub 公共仓库名称 (例如: my-docker-images): ' PUBLIC_REPO_NAME
echo

if [ -z "$PUBLIC_REPO_NAME" ]; then
    echo "错误：未输入公共仓库名称。"
    exit 1
fi

GHCR_NAMESPACE=$(echo "$GITHUB_USERNAME" | tr '[:upper:]' '[:lower:]')
IMAGE_NAME="certbot-debian-bookworm-docker-ce-cli"
IMAGE_TAG=$(date +%Y%m%d)
# 修改 FULL_IMAGE_NAME 以包含仓库名
FULL_IMAGE_NAME="ghcr.io/${GHCR_NAMESPACE}/${PUBLIC_REPO_NAME}/${IMAGE_NAME}:${IMAGE_TAG}"
LATEST_IMAGE_NAME="ghcr.io/${GHCR_NAMESPACE}/${PUBLIC_REPO_NAME}/${IMAGE_NAME}:latest" # 也更新 latest 标签名

DOCKERFILE_PATH="/opt/imagebuild/Dockerfile.certbot-debian-bookworm-docker-ce-cli"
BUILD_CONTEXT="/opt/imagebuild/"

# --- 步骤 ---
echo -e "\n--- 1. 创建 目录 ---"
mkdir -p /opt/imagebuild && cd /opt/imagebuild

echo -e "\n--- 2. 创建 Dockerfile ---"
cat > "${DOCKERFILE_PATH}" <<EOF_CER_IMG
# 使用一个轻量级的 Debian 镜像作为基础
FROM debian:bookworm-slim

# 设置非交互式安装，避免提示
ENV DEBIAN_FRONTEND=noninteractive

# 添加 Docker 官方 GPG 密钥和软件源
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        gnupg && \
    install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc && \
    chmod a+r /etc/apt/keyrings/docker.asc && \
    echo \
      "deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
      \$(. /etc/os-release && echo "\$VERSION_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null

# 更新包列表并安装依赖
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        certbot \
        python3-certbot-dns-cloudflare \
        docker-ce-cli && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# 设置 Certbot 的工作目录（可选）
WORKDIR /etc/letsencrypt

CMD ["certbot", "--help"]
EOF_CER_IMG

echo -e "\n--- Dockerfile 制作完成 ---"

echo -e "\n--- 3. 登录到 ghcr.io ---"
echo "$SCRIPT_CR_PAT" | docker login ghcr.io -u "$GITHUB_USERNAME" --password-stdin
login_exit_code=$?
# unset SCRIPT_CR_PAT # 考虑在这里 unset，如果后续步骤不再需要它。但如果脚本中其他地方可能要用，就先留着。
if [ $login_exit_code -ne 0 ]; then
    echo "错误：Docker 登录 ghcr.io 失败！请检查用户名和 PAT。"
    # 确保在退出前 unset PAT
    unset SCRIPT_CR_PAT
    exit 1
fi
echo "登录成功！"

echo -e "\n--- 4. 构建镜像 ---"
echo "构建镜像: ${FULL_IMAGE_NAME}"
docker build -t "${FULL_IMAGE_NAME}" -f "${DOCKERFILE_PATH}" "${BUILD_CONTEXT}"
if [ $? -ne 0 ]; then
    echo "错误：Docker build 失败！"
    unset SCRIPT_CR_PAT
    exit 1
fi
echo "镜像构建成功！"

echo -e "\n--- 5. 添加 latest 标签 ---"
docker tag "${FULL_IMAGE_NAME}" "${LATEST_IMAGE_NAME}"

echo -e "\n--- 6. 推送镜像到 ghcr.io ---"
echo "推送镜像: ${FULL_IMAGE_NAME}"
docker push "${FULL_IMAGE_NAME}"
if [ $? -ne 0 ]; then
    echo "错误：Docker push ${FULL_IMAGE_NAME} 失败！"
    unset SCRIPT_CR_PAT
    exit 1
fi
echo "镜像推送成功！"

echo -e "\n--- 7. 推送 latest 标签 ---"
echo "推送镜像: ${LATEST_IMAGE_NAME}"
docker push "${LATEST_IMAGE_NAME}"
if [ $? -ne 0 ]; then
    echo "错误：Docker push ${LATEST_IMAGE_NAME} 失败！"
    unset SCRIPT_CR_PAT
    exit 1
fi
echo "latest 标签推送成功！"

# 确保在脚本末尾或任何退出路径前 unset PAT
unset SCRIPT_CR_PAT

echo -e "\n--- 完成 ---"
echo "镜像 ${FULL_IMAGE_NAME} 已成功推送到 ghcr.io"
echo "你可以在 GitHub Packages 页面查看: https://github.com/orgs/${GHCR_NAMESPACE}/packages?repo_name=${PUBLIC_REPO_NAME} (如果组织) 或 https://github.com/${GHCR_NAMESPACE}?tab=packages&repo_name=${PUBLIC_REPO_NAME}"
echo "或者直接访问仓库的 Packages 标签页: https://github.com/${GHCR_NAMESPACE}/${PUBLIC_REPO_NAME}/pkgs/container/${IMAGE_NAME}"