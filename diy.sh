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
		local FOUND_DIRS=$(find "$FEEDS_LUCI" "$FEEDS_PACKAGES" "$PKG_PATH/feeds" "$PKG_PATH" -maxdepth 3 \( -type d -o -type l \) -iname "*$NAME*" 2>/dev/null)

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
	git clone --depth=1 --single-branch --branch "$PKG_BRANCH" "https://github.com/$PKG_REPO.git" || \
		git clone --depth=1 "https://github.com/$PKG_REPO.git"

	if [[ "$PKG_SPECIAL" == "pkg" ]]; then
		find ./"$REPO_NAME"/*/ -maxdepth 3 -type d -iname "*$PKG_NAME*" -prune -exec cp -rf {} ./ \;
		rm -rf ./"$REPO_NAME"/
	elif [[ "$PKG_SPECIAL" == "name" ]]; then
		mv -f "$REPO_NAME" "$PKG_NAME"
	fi
	cd "$WRT_ROOT" || return 1
}

echo ">>> [1/3] 开始拉取自定义软件包..."

# 主题与主题配置插件 (sbwml/luci-theme-argon 内已自带主题与 luci-app-argon-config)
UPDATE_PACKAGE "argon" "sbwml/luci-theme-argon" "master"
UPDATE_PACKAGE "aurora" "eamonxg/luci-theme-aurora" "master"
UPDATE_PACKAGE "aurora-config" "eamonxg/luci-app-aurora-config" "master"

# 核心代理与虚拟组网
UPDATE_PACKAGE "openclash" "vernesong/OpenClash" "dev" "pkg"
UPDATE_PACKAGE "easytier" "EasyTier/luci-app-easytier" "main"

# 实用系统管理与 5G 短信网页端工具
UPDATE_PACKAGE "diskmanager" "4IceG/luci-app-mini-diskmanager" "main"
UPDATE_PACKAGE "partexp" "sirpdboy/luci-app-partexp" "main"
UPDATE_PACKAGE "viking" "VIKINGYFY/packages" "main" "" "gecoosac luci-app-wolultra"
UPDATE_PACKAGE "sms-tool-js" "4IceG/luci-app-sms-tool-js" "main"

# H5000M / MT5700M 5G 模组控制插件 (彻底清理 mt5700/mt5700m 旧目录，拉取 LianXia233/luci-app-mt5700m)
UPDATE_PACKAGE "luci-app-h5000m-fancontrol" "FAN789/luci-app-h5000m-fancontrol" "main"
UPDATE_PACKAGE "luci-app-mt5700m" "LianXia233/luci-app-mt5700m" "main" "" "luci-app-mt5700 mt5700"
UPDATE_PACKAGE "luci-app-h5000m-netmode" "FAN789/luci-app-h5000m-netmode" "main"

if [ -f "$GITHUB_WORKSPACE/PRIVATE.sh" ]; then
	source "$GITHUB_WORKSPACE/PRIVATE.sh"
elif [ -f "$GITHUB_WORKSPACE/Scripts/PRIVATE.sh" ]; then
	source "$GITHUB_WORKSPACE/Scripts/PRIVATE.sh"
fi

# ==============================================================================
# 第二部分：运行期修补与预置内核
# ==============================================================================

echo " "
echo ">>> [2/3] 开始修补配置文件并预置 OpenClash 内核..."

ARGON_CFG="$(find "$PKG_PATH" "$FEEDS_LUCI" -type f -path "*/luci-app-argon-config/root/etc/config/argon" 2>/dev/null | head -n 1)"
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

# 预置 OpenClash Meta (Mihomo) arm64 内核到 $WRT_ROOT/files 覆盖层（设置 30 秒最大超时防卡死）
CLASH_CORE_DIR="$WRT_ROOT/files/etc/openclash/core"
mkdir -p "$CLASH_CORE_DIR"
if curl -sL --retry 2 --connect-timeout 15 --max-time 30 "https://raw.githubusercontent.com/vernesong/OpenClash/core/dev/meta/clash-linux-arm64.tar.gz" | tar xz -C "$CLASH_CORE_DIR" 2>/dev/null; then
	if [ -f "$CLASH_CORE_DIR/clash" ]; then
		mv -f "$CLASH_CORE_DIR/clash" "$CLASH_CORE_DIR/clash_meta"
		chmod +x "$CLASH_CORE_DIR/clash_meta"
		echo "OpenClash Meta core has been pre-installed!"
	fi
fi

# ==============================================================================
# 第三部分：系统配置与网络参数调整
# ==============================================================================

echo " "
echo ">>> [3/3] 开始注入系统配置与默认参数..."

if [ -d "$FEEDS_LUCI/collections" ]; then
	find "$FEEDS_LUCI/collections/" -type f -name "Makefile" -exec sed -i "/attendedsysupgrade/d" {} +
	find "$FEEDS_LUCI/collections/" -type f -name "Makefile" -exec sed -i "s/luci-theme-bootstrap/luci-theme-$WRT_THEME/g" {} +
fi

FLASH_JS=$(find "$FEEDS_LUCI/modules/luci-mod-system/" -type f -name "flash.js" 2>/dev/null | head -n 1)
if [ -n "$FLASH_JS" ]; then
	sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" "$FLASH_JS"
fi

SYSTEM_JS=$(find "$FEEDS_LUCI/modules/luci-mod-status/" -type f -name "10_system.js" 2>/dev/null | head -n 1)
if [ -n "$SYSTEM_JS" ]; then
	sed -i "s/\(luciversion || ''\)/\1 + ' \/ $WRT_MARK-$WRT_DATE'/g" "$SYSTEM_JS"
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

# 5G CPE 防运营商热点限速检测：固定数据包 TTL 为 64
NFT_TTL_DIR="$WRT_ROOT/files/etc/nftables.d"
mkdir -p "$NFT_TTL_DIR"
cat > "$NFT_TTL_DIR/99-ttl-fix.nft" <<'EOF'
chain mangle_postrouting_ttl {
	type filter hook postrouting priority 300; policy accept;
	ip ttl set 64
	ip6 hoplimit set 64
}
EOF
echo "5G CPE TTL=64 anti-detection rule has been injected!"

# ==========================================
# 预置并绑定你的 GitHub 仓库与国内加速到 OTA 升级插件
# ==========================================
OTA_CONF="$WRT_ROOT/files/etc/config/ota"
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