#!/bin/zsh
# 构建 ICT.app（只需要 Xcode 命令行工具）。
#   scripts/build-app.sh              构建到 build/ICT.app（本机芯片）
#   scripts/build-app.sh --install    另外替换“应用程序”文件夹（/Applications）里的 ICT 并打开
#   scripts/build-app.sh --universal  构建 Apple 芯片和 Intel 通用的版本（发布用，见 scripts/package-release.sh）
set -euo pipefail
cd "$(dirname "$0")/.."

INSTALL=0
ARCHS=()
for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=1 ;;
    --universal) ARCHS=(--arch arm64 --arch x86_64) ;;
    *) echo "未知参数：$arg" >&2; exit 1 ;;
  esac
done

export ICT_SDK_VERSION="$(xcrun --show-sdk-version)"
# 不同芯片的编译结果放在同一个输出目录里，后编的覆盖先编的；每次都按这次要的芯片重新编译。
swift build -c release --product ICT "${ARCHS[@]}"

APP="build/ICT.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --product ICT "${ARCHS[@]}" --show-bin-path)/ICT" "$APP/Contents/MacOS/ICT"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# 界面文字：中文、英文对照表与本地化的应用名称、权限说明。
cp -R Resources/*.lproj "$APP/Contents/Resources/"
# 程序坞、Finder 里的图标（scripts/make-icon.swift 生成）。
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
date "+%Y-%m-%d %H:%M:%S" > "$APP/Contents/Resources/BuildInfo.txt"

# 签名：有本机证书（scripts/make-signing-cert.sh 创建）就用它，签名身份固定，重新构建后不会再询问麦克风/录音权限；
# 没有就用 ad-hoc 签名（每次构建签名都会变，系统会重新询问权限）。
IDENTITY="ICT Local Signing"
if security find-identity -p codesigning | grep -q "\"$IDENTITY\""; then
  codesign --force --sign "$IDENTITY" --identifier com.ict.app "$APP"
else
  echo "⚠️  没有找到“$IDENTITY”证书，使用 ad-hoc 签名（运行 scripts/make-signing-cert.sh 可以避免每次重新授权）"
  codesign --force --sign - --identifier com.ict.app "$APP"
fi
echo "✅ 已生成 $APP"

if (( INSTALL )); then
  # 和下载安装的是同一个位置，免得有两份 ICT（Spotlight、程序坞可能打开旧的那份）。
  rm -rf /Applications/ICT.app
  ditto "$APP" /Applications/ICT.app
  echo "✅ 已安装到 /Applications/ICT.app"
  open /Applications/ICT.app
fi
