#!/bin/sh

DEST_BIN_DIR=/data/adb/ksu/bin
PERSISTENT_DIR=/data/adb/ReSuSFS

. "$MODPATH/utils.sh"

export MODULE_HOT_INSTALL_REQUEST="true"
export MODULE_HOT_RUN_SCRIPT="hotinstall.sh"

banner "$MODPATH"

ui_print "[%] customize.sh "

# cli branch: the upstream installer decides how an update treats your configs
# through volume-key prompts, which can't run unattended (adb / fleet installs).
# This branch replaces those prompts with a plain config file:
#
#   /data/adb/ReSuSFS/cli.conf
#
#   update_configs     true|false (default false)
#                      Apply the module's default configs on update — what the
#                      upstream "Do you want to update the configs?" prompt
#                      controls. Setting it true is the confirmation for
#                      replacing your config files; back up /data/adb/ReSuSFS
#                      first (upstream asks for a backup confirmation; this
#                      branch treats the explicit true in the file as that
#                      confirmation).
#   overwrite_changed  true|false (default true, used when update_configs=true)
#                      false keeps your modified copies of files that differ
#                      from the module defaults and only installs new ones.
#
# Unknown keys are ignored; invalid values fall back to the default with a
# warning. A flash with no /data/adb/ReSuSFS (or nothing in it besides this
# file) is a fresh install: every module config is copied, no keys consulted.

CONFIGURE=false
OVERWRITE_CHANGED=true

normalize_bool() {
	case "$1" in
		true | 1 | yes | TRUE | YES) echo true ;;
		false | 0 | no | FALSE | NO) echo false ;;
		*) echo "" ;;
	esac
}

CONFIG_DIR="$MODPATH/configs"

[ ! -d "$CONFIG_DIR" ] || [ -z "$(ls -A "$CONFIG_DIR" 2>/dev/null)" ] && ui_print "[!] No config files found" && exit 0

if [ -d "$PERSISTENT_DIR" ]; then
	existing=$(ls -A "$PERSISTENT_DIR" 2>/dev/null | grep -v '^cli\.conf$' | head -n1)
	if [ -n "$existing" ]; then
		CLI_CONF="$PERSISTENT_DIR/cli.conf"
		if [ -f "$CLI_CONF" ]; then
			. "$CLI_CONF"
		fi
		val=$(normalize_bool "${update_configs:-}")
		if [ -n "$val" ]; then
			CONFIGURE=$val
		elif [ -n "${update_configs:-}" ]; then
			ui_print "[!] cli.conf: invalid update_configs='$update_configs', using false"
		fi
		val=$(normalize_bool "${overwrite_changed:-}")
		if [ -n "$val" ]; then
			OVERWRITE_CHANGED=$val
		elif [ -n "${overwrite_changed:-}" ]; then
			ui_print "[!] cli.conf: invalid overwrite_changed='$overwrite_changed', using true"
		fi
		if $CONFIGURE; then
			ui_print "[*] update_configs=true: applying module default configs"
			! $OVERWRITE_CHANGED && ui_print "[*] overwrite_changed=false: keeping your changed files"
		else
			ui_print "[*] update_configs=false: keeping existing configs"
		fi
	fi
fi

handle_files() {
	src_dir="$1"
	dst_dir="$2"
	files="$3"
	action="$4"
	DIFFERENT=""
	for file in $files; do
		src="$src_dir/$file"
		dst="$dst_dir/$file"
		if [ ! -f "$dst" ]; then
			mkdir -p "$dst_dir/$(dirname "$file")"
			cp "$src" "$dst"
			ui_print "[+] $file copied"
		elif ! cmp -s "$src" "$dst"; then
			if $OVERWRITE_CHANGED; then
				mkdir -p "$dst_dir/$(dirname "$file")"
				cp "$src" "$dst"
				ui_print "[+] $file $action"
			else
				DIFFERENT="$DIFFERENT $file"
			fi
		fi
	done
	if [ -n "$DIFFERENT" ]; then
		ui_print "[*] Kept changed files (set overwrite_changed=true to replace):"
		for file in $DIFFERENT; do
			ui_print "    - $file"
		done
	fi
}

if $CONFIGURE; then
	handle_files "$CONFIG_DIR" "$PERSISTENT_DIR" "scripts_bootcompleted.txt scripts_postfs.txt" "updated"
	if [ -d "$CONFIG_DIR/scripts" ]; then
		handle_files "$CONFIG_DIR/scripts" "$PERSISTENT_DIR/scripts" "$(get_all_files "$CONFIG_DIR/scripts")" "updated"
	fi

	CONFIG_FILES=$(get_all_files "$CONFIG_DIR" | grep -v '^scripts/')
	[ -n "$CONFIG_FILES" ] && handle_files "$CONFIG_DIR" "$PERSISTENT_DIR" "$CONFIG_FILES" "reset"
fi

rm -rf "$CONFIG_DIR"

download_susfs_guard_lkm
update_susfs || exit 1

chmod 755 "$MODPATH/ReSuSFS.sh"
chmod 644 "$MODPATH/post-fs-data.sh" "$MODPATH/service.sh" "$MODPATH/uninstall.sh" 2>/dev/null

if [ -d "$DEST_BIN_DIR" ]; then
	ui_print "[+] creating symlink in $DEST_BIN_DIR"
	ln -sf "/data/adb/modules/ReSuSFS/ReSuSFS.sh" "$DEST_BIN_DIR/ReSuSFS"
fi

if [ ! -d "$PERSISTENT_DIR/.webui_config" ] || [ ! -f "$PERSISTENT_DIR/.webui_config/custom.css" ]; then
	mkdir -p "$PERSISTENT_DIR/.webui_config"
	mv "$MODPATH/custom.css" "$PERSISTENT_DIR/.webui_config/custom.css"
else
	rm -f "$MODPATH/custom.css"
fi

# EOF
