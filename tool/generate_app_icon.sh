#!/usr/bin/env bash
# 从 assets/branding/flux-app-icon.svg 生成 macOS AppIcon 全尺寸 PNG（T051）。
#
# 为什么用一个脚本而不是手放七张图：
#   「设计源改一次、七个尺寸全都更新」是这份图标能长期维护的前提。手放图片时，
#   改了大图忘了小图是必然会发生的，而那种不一致只在 Dock 的特定缩放下才看得见。
#
# 依赖：rsvg-convert（Homebrew librsvg）。选它而不是 qlmanage/sips 直接转：
#   sips 不读 SVG，qlmanage 走 QuickLook 会引入它自己的边距与背景；rsvg-convert 是
#   纯粹的 SVG 光栅化，目标尺寸直接渲染（也就是按目标分辨率做抗锯齿），16px 不会
#   因为是「大图缩小」而糊掉。
#
# 用法：tool/generate_app_icon.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$REPO_ROOT/assets/branding/flux-app-icon.svg"
TARGET_DIR="$REPO_ROOT/macos/Runner/Assets.xcassets/AppIcon.appiconset"

if ! command -v rsvg-convert >/dev/null 2>&1; then
  echo "缺少 rsvg-convert（brew install librsvg）" >&2
  exit 1
fi

# Contents.json 引用的全部像素尺寸：16/32/64/128/256/512/1024。
# 其中 32 同时用于 16@2x 与 32@1x，64 用于 32@2x，512 用于 256@2x，1024 用于 512@2x。
for size in 16 32 64 128 256 512 1024; do
  rsvg-convert --width "$size" --height "$size" --output "$TARGET_DIR/app_icon_${size}.png" "$SOURCE"
  echo "生成 app_icon_${size}.png"
done

# 收尾校验：macOS 只接受 RGB/RGBA 的 PNG，且尺寸必须与文件名一致。
for size in 16 32 64 128 256 512 1024; do
  actual="$(sips -g pixelWidth "$TARGET_DIR/app_icon_${size}.png" | awk '/pixelWidth/ {print $2}')"
  if [ "$actual" != "$size" ]; then
    echo "app_icon_${size}.png 的宽度是 $actual，与期望不符" >&2
    exit 1
  fi
done

echo "完成：7 个尺寸已写入 $TARGET_DIR"
