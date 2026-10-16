#!/usr/bin/env bash
# ============================================================
# 一键推送 LX 音乐 iOS 客户端到 GitHub 并触发自动构建
# 用法：在项目目录（LXMusicClient-iOS）运行  ./push_to_github.sh
# 需要：安装了 git；可选：安装了 gh 且已登录（推荐，可自动建私有仓库）
# ============================================================
set -e

echo "▶ 1. 检查 git 远程"
if git remote get-url origin >/dev/null 2>&1; then
  echo "   已存在远程: $(git remote get-url origin)"
else
  # 方式 A：gh 已登录 → 自动创建私有仓库并推送
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    echo "▶ 2. 检测到 gh 已登录，创建私有仓库并推送"
    gh repo create lx-music-ios-client --private --source . --push
  else
    # 方式 B：手动指定仓库地址
    echo "▶ 2. 请先在 GitHub 网页新建一个空仓库（不要勾选初始化 README），然后粘贴地址，例如："
    echo "     https://github.com/你的用户名/lx-music-ios-client.git"
    read -rp "仓库地址: " repo_url
    git remote add origin "$repo_url"
    git push -u origin main
  fi
  echo "✔ 已推送。GitHub Actions 正在自动构建 .ipa……"
  echo "   构建完成后：仓库 → Actions → Build iOS IPA → 最新一次 → Artifacts → LXMusicClient.ipa"
fi
