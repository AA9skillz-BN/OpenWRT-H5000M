#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY

# 确保在 OpenWrt 源码根目录下运行
WRT_ROOT="$(pwd)"
PKG_PATH="$WRT_ROOT/package"
FEEDS_LUCI="$WRT_ROOT/feeds/luci"
FEEDS_PACKAGES="$WRT_ROOT/feeds/packages"

mkdir -p "$PKG_PATH"

echo "=========================================="
echo ">>> 开始执行 diy.sh (自定义组件与参数注入)"
echo "=========================================="

# ==============================================================================
# 第一部分：安装和更新软件包 (原 Packages.sh)
# ==============================================================================

UPDATE_PACKAGE() {
	local PKG_NAME=$1
	local PKG_REPO=$2
	local PKG_BRANCH=$3
	local PKG_SPECIAL=$4
	local PKG_LIST=("$PKG_NAME" $5)
	local REPO_NAME=${PKG_REPO#*/}

	echo " "

	# 清理 feeds 中可能存在的同名旧包
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

	# 克隆到 package/ 目录
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

UPDATE_PACKAGE "argon" "sbwml/luci-theme-argon" "master"
UPDATE_PACKAGE "aurora" "eamonxg/luci-theme-aurora" "master"
UPDATE_PACKAGE "aurora-config" "eamonxg/luci-app-aurora-config" "master"

UPDATE_PACKAGE "momo" "nikkinikki-org/OpenWrt-momo" "main"
UPDATE_PACKAGE "nikki" "nikkinikki-org/OpenWrt-nikki" "main"
UPDATE_PACKAGE "openclash" "vernesong/OpenClash" "dev" "pkg"
UPDATE_PACKAGE "passwall" "Openwrt-Passwall/openwrt-passwall" "main" "pkg"
UPDATE_PACKAGE "passwall2" "Openwrt-Passwall/openwrt-passwall2" "main" "pkg"

UPDATE_PACKAGE "luci-app-tailscale" "asvow/luci-app-tailscale" "main"

UPDATE_PACKAGE "ddns-go" "sirpdboy/luci-app-ddns-go" "main"
UPDATE_PACKAGE "diskman" "sbwml/luci-app-diskman" "main"
UPDATE_PACKAGE "diskmanager" "4IceG/luci-app-mini-diskmanager" "main"
UPDATE_PACKAGE "easytier" "EasyTier/luci-app-easytier" "main"
UPDATE_PACKAGE "mosdns" "sbwml/luci-app-mosdns" "v5" "" "v2dat"
UPDATE_PACKAGE "netspeedtest" "sirpdboy/netspeedtest" "main" "" "homebox ookla-speedtest"
UPDATE_PACKAGE "netwizard" "sirpdboy/luci-app-netwizard" "main"
UPDATE_PACKAGE "openlist2" "sbwml/luci-app-openlist2" "main"
UPDATE_PACKAGE "partexp" "sirpdboy/luci-app-partexp" "main"
UPDATE_PACKAGE "qbittorrent" "sbwml/luci-app-qbittorrent" "master" "" "qt6base qt6tools rblibtorrent"
UPDATE_PACKAGE "qmodem" "FUjr/QModem" "main"
UPDATE_PACKAGE "quickfile" "sbwml/luci-app-quickfile" "main"
UPDATE_PACKAGE "timecontrol" "sirpdboy/luci-app-timecontrol" "main"
UPDATE_PACKAGE "viking" "VIKINGYFY/packages" "main" "" "axonhub gecoosac sing-box luci-app-homeproxy luci-app-timewol luci-app-wolplus luci-app-wolultra"

# 清理 sing-box 过时补丁（使用动态 find 避免路径写死错位）
FIX_SINGBOX_STALE_PATCH() {
	local PATCH
	PATCH=$(find "$PKG_PATH" -type f -name "100-fix-dns-tcp-close.patch" 2>/dev/null | head -n 1)
	[ -n "$PATCH" ] && [ -f "$PATCH" ] || { echo "sing-box: 无 100-fix-dns-tcp-close.patch，跳过"; return 0; }
	if grep -q "HandleStreamDNSConnection" "$PATCH"; then
		rm -f "$PATCH"
		echo "sing-box: 移除过时补丁 $PATCH"
	else
		echo "sing-box: 补丁已非旧版，保留"
	fi
}
FIX_SINGBOX_STALE_PATCH

UPDATE_PACKAGE "vnt" "lmq8267/luci-app-vnt" "main"

# FAN789 插件
UPDATE_PACKAGE "luci-app-h5000m-fancontrol" "FAN789/luci-app-h5000m-fancontrol" "main"
UPDATE_PACKAGE "luci-app-mt5700m" "FAN789/luci-app-mt5700m" "main"
UPDATE_PACKAGE "luci-app-h5000m-netmode" "FAN789/luci-app-h5000m-netmode" "main"

# 引入私有扩展脚本
if [ -f "$GITHUB_WORKSPACE/PRIVATE.sh" ]; then
	source "$GITHUB_WORKSPACE/PRIVATE.sh"
elif [ -f "$GITHUB_WORKSPACE/Scripts/PRIVATE.sh" ]; then
	source "$GITHUB_WORKSPACE/Scripts/PRIVATE.sh"
fi

# ==============================================================================
# 第二部分：运行期数据预置与特殊修补 (原 Handles.sh)
# ==============================================================================

echo " "
echo ">>> [2/3] 开始预置资源与修补依赖..."

# 预置 HomeProxy 数据
HP_DIR="$(find "$PKG_PATH" -maxdepth 2 -type d -name '*homeproxy*' -print -quit)"
if [ -n "$HP_DIR" ]; then
	echo "找到 HomeProxy 目录: $HP_DIR"

	HP_RESOURCES="$HP_DIR/root/etc/homeproxy/resources"
	HP_DASHBOARD="$HP_DIR/root/etc/homeproxy/dashboard"
	HP_IP_SOURCE="https://cdn.jsdelivr.net/gh/Loyalsoldier/surge-rules@release/cncidr.txt"
	HP_GEOSITE_SOURCE="https://cdn.jsdelivr.net/gh/SagerNet/sing-geosite@rule-set-unstable/geosite-cn.srs"
	HP_IP_VERSION_URL="https://github.com/Loyalsoldier/surge-rules/releases/latest"
	HP_GEOSITE_VERSION_URL="https://github.com/SagerNet/sing-geosite/releases/latest"
	HP_DASHBOARD_SOURCE="https://codeload.github.com/SagerNet/sing-box-dashboard/zip/refs/heads/gh-pages"
	HP_DASHBOARD_VERSION_URL="https://github.com/SagerNet/sing-box-dashboard/commits/gh-pages.atom"
	HP_USER_AGENT="HomeProxy resource preset"

	HP_PREREQUISITES_MISSING=0
	for HP_COMMAND in curl awk unzip; do
		command -v "$HP_COMMAND" > /dev/null 2>&1 || {
			echo "homeproxy resource preset requires $HP_COMMAND!"
			HP_PREREQUISITES_MISSING=1
		}
	done

	HP_PRESET_FAILED=0
	if [ "${HP_PREREQUISITES_MISSING:-0}" -eq 1 ]; then
		HP_PRESET_FAILED=1
	else
		HP_TMP="$(mktemp -d)"
		if [ -z "$HP_TMP" ]; then
			echo "failed to prepare homeproxy resource preset directory!"
			HP_PRESET_FAILED=1
		fi
	fi
	HP_DASHBOARD_STAGE="${HP_DASHBOARD}.new.$$"

	hp_fetch_release_version() {
		local effective_url version
		effective_url="$(curl -fsSL --compressed --retry 3 --retry-all-errors \
			--retry-delay 1 --connect-timeout 10 --max-time 30 -A "$HP_USER_AGENT" \
			-o /dev/null -w '%{url_effective}' "$1")" || return 1
		version="${effective_url##*/}"
		case "$version" in
		''|*[!0-9]*) return 1 ;;
		esac
		printf '%s\n' "$version"
	}

	hp_download() {
		curl -fsSL --compressed --retry 3 --retry-all-errors --retry-delay 1 \
			--connect-timeout 10 --max-time 60 -A "$HP_USER_AGENT" -o "$2" "$1" && [ -s "$2" ]
	}

	hp_fetch_dashboard_version() {
		local feed version
		feed="$(curl -fsSL --compressed --retry 3 --retry-all-errors \
			--retry-delay 1 --connect-timeout 10 --max-time 30 \
			-A "$HP_USER_AGENT" "$HP_DASHBOARD_VERSION_URL")" || return 1
		version="$(printf '%s\n' "$feed" | awk -F '[<>]' '
			/<updated>/ {
				version = $3
				gsub(/[-:TZ]/, "", version)
				print version
				exit
			}
		')"
		case "$version" in
		??????????????) case "$version" in *[!0-9]*) return 1 ;; esac ;;
		*) return 1 ;;
		esac
		printf '%s\n' "$version"
	}

	hp_replace_file() {
		local source_file="$1" target_file="$2" temporary_file
		temporary_file="${target_file}.tmp.$$"
		cp "$source_file" "$temporary_file" || return 1
		chmod 0644 "$temporary_file" || return 1
		mv -f "$temporary_file" "$target_file"
	}

	hp_update_ip() {
		local version file
		version="$(hp_fetch_release_version "$HP_IP_VERSION_URL")" || return 1
		hp_download "$HP_IP_SOURCE?v=$version" "$HP_TMP/cncidr.txt" || return 1
		awk -F, -v ipv4="$HP_TMP/china_ip4.txt" -v ipv6="$HP_TMP/china_ip6.txt" '
			$1 == "IP-CIDR" { print $2 > ipv4 }
			$1 == "IP-CIDR6" { print $2 > ipv6 }
		' "$HP_TMP/cncidr.txt" || return 1
		[ -s "$HP_TMP/china_ip4.txt" ] && [ -s "$HP_TMP/china_ip6.txt" ] || return 1
		awk '
			BEGIN {
				print "{\"version\":5,\"rules\":[{\"ip_cidr\":["
				first = 1
			}
			NF {
				printf "%s\"%s\"", first ? "" : ",", $0
				first = 0
			}
			END { print "]}]}" }
		' "$HP_TMP/china_ip4.txt" "$HP_TMP/china_ip6.txt" > "$HP_TMP/geoip_cn.json" || return 1
		[ -s "$HP_TMP/geoip_cn.json" ] || return 1
		printf '%s\n' "$version" > "$HP_TMP/china_ip4.ver"
		printf '%s\n' "$version" > "$HP_TMP/china_ip6.ver"
		for file in china_ip4.txt china_ip4.ver china_ip6.txt china_ip6.ver geoip_cn.json; do
			hp_replace_file "$HP_TMP/$file" "$HP_RESOURCES/$file" || return 1
		done
		echo "homeproxy resources: china_ip $version"
	}

	hp_update_geosite() {
		local version
		version="$(hp_fetch_release_version "$HP_GEOSITE_VERSION_URL")" || return 1
		hp_download "$HP_GEOSITE_SOURCE?v=$version" "$HP_TMP/geosite_cn.srs" || return 1
		printf '%s\n' "$version" > "$HP_TMP/geosite_cn.ver"
		hp_replace_file "$HP_TMP/geosite_cn.srs" "$HP_RESOURCES/geosite_cn.srs" || return 1
		hp_replace_file "$HP_TMP/geosite_cn.ver" "$HP_RESOURCES/geosite_cn.ver" || return 1
		echo "homeproxy resources: geosite_cn $version"
	}

	hp_update_dashboard() {
		local version source_dir old_dir
		version="$(hp_fetch_dashboard_version)" || return 1
		hp_download "$HP_DASHBOARD_SOURCE?v=$version" "$HP_TMP/dashboard.zip" || return 1
		unzip -q "$HP_TMP/dashboard.zip" -d "$HP_TMP/dashboard" || return 1
		source_dir="$(find "$HP_TMP/dashboard" -mindepth 1 -maxdepth 1 -type d -print -quit)"
		[ -n "$source_dir" ] && [ -f "$source_dir/index.html" ] || return 1

		rm -rf "$HP_DASHBOARD_STAGE"
		mkdir -p "$HP_DASHBOARD_STAGE" &&
			cp -a "$source_dir/." "$HP_DASHBOARD_STAGE/" &&
			printf '%s\n' "$version" > "$HP_DASHBOARD_STAGE/dashboard.ver" || return 1
		rm -f "$HP_DASHBOARD_STAGE/.etag"
		chmod -R a+rX "$HP_DASHBOARD_STAGE" || return 1

		old_dir="${HP_DASHBOARD}.old.$$"
		rm -rf "$old_dir"
		{ [ ! -d "$HP_DASHBOARD" ] || mv "$HP_DASHBOARD" "$old_dir"; } || return 1
		if mv "$HP_DASHBOARD_STAGE" "$HP_DASHBOARD"; then
			rm -rf "$old_dir"
			echo "homeproxy dashboard: $version"
			return 0
		fi
		rm -rf "$HP_DASHBOARD"
		[ ! -d "$old_dir" ] || mv "$old_dir" "$HP_DASHBOARD"
		return 1
	}

	if [ "$HP_PRESET_FAILED" -eq 0 ] && mkdir -p "$HP_RESOURCES" "$HP_DASHBOARD"; then
		hp_update_ip || echo "failed to update homeproxy IP resources; continuing!"
		hp_update_geosite || echo "failed to update homeproxy geosite; continuing!"
		hp_update_dashboard || echo "failed to update homeproxy dashboard; continuing!"
		rm -rf "$HP_TMP" "$HP_DASHBOARD_STAGE"
		echo "homeproxy data preset finished!"
	fi
fi

# 修改 argon 主题
ARGON_CFG="$(find "$PKG_PATH" -type f -path "*/luci-app-argon-config/root/etc/config/argon" 2>/dev/null | head -n 1)"
if [ -f "$ARGON_CFG" ]; then
	sed -i "s/primary '.*'/primary '#31a1a1'/; s/'0.2'/'0.5'/; s/'none'/'bing'/; s/'600'/'normal'/" "$ARGON_CFG"
	echo "theme-argon has been fixed!"
fi

# 修改 aurora 菜单式样
AURORA_DIR="$(find "$PKG_PATH" -type d -path "*/luci-app-aurora-config/root/usr/share/aurora" 2>/dev/null | head -n 1)"
if [ -d "$AURORA_DIR" ]; then
	find "$AURORA_DIR" -type f -name '*.template' -exec \
		sed -i "s/nav_type '.*'/nav_type 'dropdown'/g; s/struct_radius_base '.*'/struct_radius_base '0.125rem'/g" {} +
	echo "theme-aurora has been fixed!"
fi

# 修改 mini-diskmanager 菜单位置
MINI_DM_JSON="$(find "$PKG_PATH" -type f -name "luci-app-mini-diskmanager.json" 2>/dev/null | head -n 1)"
if [ -f "$MINI_DM_JSON" ]; then
	sed -i "s/services/system/g" "$MINI_DM_JSON"
	echo "mini-diskmanager has been fixed!"
fi

# 修复 Tailscale 配置文件冲突
TS_MAKEFILE="$(find "$FEEDS_PACKAGES" -maxdepth 3 -type f -wholename '*/tailscale/Makefile' 2>/dev/null | head -n 1)"
if [ -f "$TS_MAKEFILE" ]; then
	sed -i '/\/files/d' "$TS_MAKEFILE"
	echo "tailscale Makefile has been fixed!"
fi

# 修复 Rust 编译失败
RUST_MAKEFILE="$(find "$FEEDS_PACKAGES" -maxdepth 3 -type f -wholename '*/rust/Makefile' 2>/dev/null | head -n 1)"
if [ -f "$RUST_MAKEFILE" ]; then
	sed -i 's/ci-llvm=true/ci-llvm=false/g' "$RUST_MAKEFILE"
	echo "rust Makefile has been fixed!"
fi

# ==============================================================================
# 第三部分：系统配置与网络参数调整 (原 Settings.sh)
# ==============================================================================

echo " "
echo ">>> [3/3] 开始注入系统配置与默认参数..."

# 移除 luci-app-attendedsysupgrade
sed -i "/attendedsysupgrade/d" $(find "$FEEDS_LUCI/collections/" -type f -name "Makefile" 2>/dev/null)

# 修改默认主题
sed -i "s/luci-theme-bootstrap/luci-theme-$WRT_THEME/g" $(find "$FEEDS_LUCI/collections/" -type f -name "Makefile" 2>/dev/null)

# 修改 immortalwrt.lan 关联 IP
sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" $(find "$FEEDS_LUCI/modules/luci-mod-system/" -type f -name "flash.js" 2>/dev/null)

# 添加编译日期标识
sed -i "s/(\(luciversion || ''\))/(\1) + (' \/ $WRT_MARK-$WRT_DATE')/g" $(find "$FEEDS_LUCI/modules/luci-mod-status/" -type f -name "10_system.js" 2>/dev/null)

# 修改默认 Wi-Fi SSID 与密码
WIFI_SH=$(find "$WRT_ROOT/target/linux/mediatek/filogic/base-files/etc/uci-defaults/" -type f -name "*set-wireless.sh" 2>/dev/null | head -n 1)
WIFI_UC="$WRT_ROOT/package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc"
if [ -f "$WIFI_SH" ]; then
	sed -i "s/BASE_SSID='.*'/BASE_SSID='$WRT_SSID'/g" "$WIFI_SH"
	sed -i "s/BASE_WORD='.*'/BASE_WORD='$WRT_WORD'/g" "$WIFI_SH"
elif [ -f "$WIFI_UC" ]; then
	sed -i "s/ssid='.*'/ssid='$WRT_SSID'/g" "$WIFI_UC"
	sed -i "s/key='.*'/key='$WRT_WORD'/g" "$WIFI_UC"
fi

# 修改默认 IP 与 Hostname
CFG_FILE="$WRT_ROOT/package/base-files/files/bin/config_generate"
if [ -f "$CFG_FILE" ]; then
	sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" "$CFG_FILE"
	sed -i "s/hostname='.*'/hostname='$WRT_NAME'/g" "$CFG_FILE"
fi

# 基础 LuCI 与主题配置追加
{
	echo "CONFIG_PACKAGE_luci=y"
	echo "CONFIG_LUCI_LANG_zh_Hans=y"
	echo "CONFIG_PACKAGE_luci-theme-$WRT_THEME=y"
	echo "CONFIG_PACKAGE_luci-app-$WRT_THEME-config=y"
} >> "$WRT_ROOT/.config"

# 引入私有扩展配置
if [ -f "$GITHUB_WORKSPACE/PRIVATE.txt" ]; then
	echo "Applying private configurations from PRIVATE.txt..."
	cat "$GITHUB_WORKSPACE/PRIVATE.txt" >> "$WRT_ROOT/.config"
elif [ -f "$GITHUB_WORKSPACE/Config/PRIVATE.txt" ]; then
	echo "Applying private configurations from Config/PRIVATE.txt..."
	cat "$GITHUB_WORKSPACE/Config/PRIVATE.txt" >> "$WRT_ROOT/.config"
fi

# 手动调整插件追加
if [ -n "$WRT_PACKAGE" ]; then
	echo -e "$WRT_PACKAGE" >> "$WRT_ROOT/.config"
fi

echo " "
echo "=========================================="
echo ">>> diy.sh 全部执行完毕！"
echo "=========================================="
