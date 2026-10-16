#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY

# 确保在 OpenWrt 源码根目录下运行
WRT_ROOT="${GITHUB_WORKSPACE}/wrt"
PKG_PATH="$WRT_ROOT/package"
FEEDS_LUCI="$WRT_ROOT/feeds/luci"
FEEDS_PACKAGES="$WRT_ROOT/feeds/packages"

mkdir -p "$PKG_PATH"

echo "=========================================="
echo ">>> 开始执行 diy.sh (自定义组件与参数注入)"
echo "=========================================="

# ==============================================================================
# 第一部分：安装和更新软件包
# ==============================================================================

UPDATE_PACKAGE() {
	local PKG_NAME=$1
	local PKG_REPO=$2
	local PKG_BRANCH=$3
	local PKG_SPECIAL=$4
	local PKG_LIST=("$PKG_NAME" $5)
	local REPO_NAME=${PKG_REPO#*/}

	echo " "

	for NAME in "${PKG_LIST[@]}"; do
		echo "Search directory: $NAME"
		local FOUND_DIRS=$(find "$FEEDS_LUCI" "$FEEDS_PACKAGES" -maxdepth 3 -type d -iname "*$NAME*" 2>/dev/null)

		if [ -n "$FOUND_DIRS" ]; then
			while read -r DIR; do
				rm -rf "$DIR"
				echo "Delete directory: $DIR"
			done <<< "$FOUND_DIRS"
		else
			echo "Not found directory: $NAME"
		fi
	done

	cd "$PKG_PATH" || return 1
	git clone --depth=1 --single-branch --branch "$PKG_BRANCH" "https://github.com/$PKG_REPO.git"

	if [[ "$PKG_SPECIAL" == "pkg" ]]; then
		find ./"$REPO_NAME"/*/ -maxdepth 3 -type d -iname "*$PKG_NAME*" -prune -exec cp -rf {} ./ \;
		rm -rf ./"$REPO_NAME"/
	elif [[ "$PKG_SPECIAL" == "name" ]]; then
		mv -f "$REPO_NAME" "$PKG_NAME"
	fi
	cd "$WRT_ROOT" || return 1
}

echo ">>> [1/3] 开始拉取自定义软件包..."

# 主题
UPDATE_PACKAGE "argon" "sbwml/luci-theme-argon" "master"
UPDATE_PACKAGE "aurora" "eamonxg/luci-theme-aurora" "master"
UPDATE_PACKAGE "aurora-config" "eamonxg/luci-app-aurora-config" "master"

# 核心代理与虚拟组网
UPDATE_PACKAGE "openclash" "vernesong/OpenClash" "dev" "pkg"
UPDATE_PACKAGE "easytier" "EasyTier/luci-app-easytier" "main"

# 实用系统管理工具
UPDATE_PACKAGE "diskmanager" "4IceG/luci-app-mini-diskmanager" "main"
UPDATE_PACKAGE "partexp" "sirpdboy/luci-app-partexp" "main"
UPDATE_PACKAGE "viking" "VIKINGYFY/packages" "main" "" "gecoosac luci-app-wolultra"

# H5000M / MT5700M 5G 模组控制插件
UPDATE_PACKAGE "luci-app-h5000m-fancontrol" "FAN789/luci-app-h5000m-fancontrol" "main"
UPDATE_PACKAGE "luci-app-mt5700m" "FAN789/luci-app-mt5700m" "main"
UPDATE_PACKAGE "luci-app-h5000m-netmode" "FAN789/luci-app-h5000m-netmode" "main"

if [ -f "$GITHUB_WORKSPACE/PRIVATE.sh" ]; then
	source "$GITHUB_WORKSPACE/PRIVATE.sh"
elif [ -f "$GITHUB_WORKSPACE/Scripts/PRIVATE.sh" ]; then
	source "$GITHUB_WORKSPACE/Scripts/PRIVATE.sh"
fi

# ==============================================================================
# 第二部分：运行期修补
# ==============================================================================

echo " "
echo ">>> [2/3] 开始修补配置文件..."

ARGON_CFG="$(find "$PKG_PATH" -type f -path "*/luci-app-argon-config/root/etc/config/argon" 2>/dev/null | head -n 1)"
if [ -f "$ARGON_CFG" ]; then
	sed -i "s/primary '.*'/primary '#31a1a1'/; s/'0.2'/'0.5'/; s/'none'/'bing'/; s/'600'/'normal'/" "$ARGON_CFG"
	echo "theme-argon has been fixed!"
fi

AURORA_DIR="$(find "$PKG_PATH" -type d -path "*/luci-app-aurora-config/root/usr/share/aurora" 2>/dev/null | head -n 1)"
if [ -d "$AURORA_DIR" ]; then
	find "$AURORA_DIR" -type f -name '*.template' -exec \
		sed -i "s/nav_type '.*'/nav_type 'dropdown'/g; s/struct_radius_base '.*'/struct_radius_base '0.125rem'/g" {} +
	echo "theme-aurora has been fixed!"
fi

MINI_DM_JSON="$(find "$PKG_PATH" -type f -name "luci-app-mini-diskmanager.json" 2>/dev/null | head -n 1)"
if [ -f "$MINI_DM_JSON" ]; then
	sed -i "s/services/system/g" "$MINI_DM_JSON"
	echo "mini-diskmanager has been fixed!"
fi

RUST_MAKEFILE="$(find "$FEEDS_PACKAGES" -maxdepth 3 -type f -wholename '*/rust/Makefile' 2>/dev/null | head -n 1)"
if [ -f "$RUST_MAKEFILE" ]; then
	sed -i 's/ci-llvm=true/ci-llvm=false/g' "$RUST_MAKEFILE"
	echo "rust Makefile has been fixed!"
fi

# ==============================================================================
# 第三部分：系统配置与网络参数调整
# ==============================================================================

echo " "
echo ">>> [3/3] 开始注入系统配置与默认参数..."

# 修复潜在的子shell匹配逻辑及路径安全
COLLECTIONS_MAKEFILE=$(find "$FEEDS_LUCI/collections/" -type f -name "Makefile" 2>/dev/null)
if [ -n "$COLLECTIONS_MAKEFILE" ]; then
	sed -i "/attendedsysupgrade/d" $COLLECTIONS_MAKEFILE
	sed -i "s/luci-theme-bootstrap/luci-theme-$WRT_THEME/g" $COLLECTIONS_MAKEFILE
fi

FLASH_JS=$(find "$FEEDS_LUCI/modules/luci-mod-system/" -type f -name "flash.js" 2>/dev/null)
if [ -n "$FLASH_JS" ]; then
	sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" $FLASH_JS
fi

SYSTEM_JS=$(find "$FEEDS_LUCI/modules/luci-mod-status/" -type f -name "10_system.js" 2>/dev/null)
if [ -n "$SYSTEM_JS" ]; then
	sed -i "s/(\(luciversion || ''\))/(\1) + (' \/ $WRT_MARK-$WRT_DATE')/g" $SYSTEM_JS
fi

WIFI_SH=$(find "$WRT_ROOT/target/linux/mediatek/filogic/base-files/etc/uci-defaults/" -type f -name "*set-wireless.sh" 2>/dev/null | head -n 1)
WIFI_UC="$WRT_ROOT/package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc"
if [ -f "$WIFI_SH" ]; then
	sed -i "s/BASE_SSID='.*'/BASE_SSID='$WRT_SSID'/g" "$WIFI_SH"
	sed -i "s/BASE_WORD='.*'/BASE_WORD='$WRT_WORD'/g" "$WIFI_SH"
elif [ -f "$WIFI_UC" ]; then
	sed -i "s/ssid='.*'/ssid='$WRT_SSID'/g" "$WIFI_UC"
	sed -i "s/key='.*'/key='$WRT_WORD'/g" "$WIFI_UC"
fi

CFG_FILE="$WRT_ROOT/package/base-files/files/bin/config_generate"
if [ -f "$CFG_FILE" ]; then
	sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" "$CFG_FILE"
	sed -i "s/hostname='.*'/hostname='$WRT_NAME'/g" "$CFG_FILE"
fi

# ==========================================
# 预置并绑定你的 GitHub 仓库与国内加速到 OTA 升级插件
# ==========================================
OTA_CONF="$WRT_ROOT/package/base-files/files/etc/config/ota"
mkdir -p "$(dirname "$OTA_CONF")"
cat > "$OTA_CONF" <<EOF
config ota 'settings'
	option repo 'AA9skillz-BN/OpenWRT-H5000M'
	option branch 'master'
	option mirror 'https://ghfast.top/'
EOF
echo "Custom OTA repository 'AA9skillz-BN/OpenWRT-H5000M' and mirror has been bound!"

{
	echo "CONFIG_PACKAGE_luci=y"
	echo "CONFIG_LUCI_LANG_zh_Hans=y"
	echo "CONFIG_PACKAGE_luci-theme-$WRT_THEME=y"
	echo "CONFIG_PACKAGE_luci-app-$WRT_THEME-config=y"
} >> "$WRT_ROOT/.config"

if [ -f "$GITHUB_WORKSPACE/PRIVATE.txt" ]; then
	cat "$GITHUB_WORKSPACE/PRIVATE.txt" >> "$WRT_ROOT/.config"
elif [ -f "$GITHUB_WORKSPACE/Config/PRIVATE.txt" ]; then
	cat "$GITHUB_WORKSPACE/Config/PRIVATE.txt" >> "$WRT_ROOT/.config"
fi

if [ -n "$WRT_PACKAGE" ]; then
	echo -e "$WRT_PACKAGE" >> "$WRT_ROOT/.config"
fi

echo " "
echo "=========================================="
echo ">>> diy.sh 全部执行完毕! "
echo "=========================================="
