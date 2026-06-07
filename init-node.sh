#!/bin/bash

cur_dir="$(dirname "$(readlink -f "$0")")"
dl_dir="$cur_dir/dl"

source "$cur_dir/common-script.sh"

install_fnm_and_config() {
	_success=0

	if command -v fnm >/dev/null 2>&1; then
		print_log "info" "fnm is existed at $(which fnm) ... skip"
	else
		print_log "act" "install fnm ..."
		export FNM_BASE_URL="${GITHUB}"
		if curl_get_file "$dl_dir/fnm.sh" https://fnm.vercel.app/install; then
			if bash "$dl_dir/fnm.sh"; then
				print_log "suc" "install fnm by https://fnm.vercel.app/install success."
				source "$HOME/.zshrc" 2>/dev/null || true
				_success=1
			fi
			rm -f "$dl_dir/fnm.sh"
		fi

		if [[ $_success -eq 0 ]]; then
			if bash "$dl_dir/fnm-install.sh"; then
				# curl -LsSf https://fnm.vercel.app/install -o fnm-install.sh
				print_log "suc" "install fnm by $dl_dir/fnm-install.sh success."
				source "$HOME/.zshrc" 2>/dev/null || true
				_success=1
			else
				print_log "fail" "install fnm failure."
			fi
		fi
	fi

	# if ! grep -qE 'export FNM_NODE_DIST_MIRROR="?http.*' "$HOME/.zshrc"; then
	# 	echo 'export FNM_NODE_DIST_MIRROR="https://npmmirror.com/mirrors/node/"' >>"$HOME/.zshrc"
	# fi
}

fnm_install_node() {
	print_log "act" "fnm install $*"
	fnm install "$@"
}

install_node() {
	fnm_install_node 24.16.0
	fnm_install_node 26.3.0
	fnm default 24.16.0
}

npm_install_tool() {
	print_log "act" "npm install -g $*"
	npm install -g "$@"
}

install_node_tool() {
	npm_install_tool prettier
	npm_install_tool stylus
	npm_install_tool autocorrect-node
	npm_install_tool markdownlint-cli
}

install_bun() {
	if command -v bun >/dev/null 2>&1; then
		print_log "info" "bun is existed at $(which bun) ... skip"
	else
		print_log "act" "install bun ..."
		if curl -fsSL https://bun.com/install | GITHUB="$GITHUB" sh; then
			print_log "suc" "install bun by https://bun.com/install success."
		else
			print_log "fail" "install bun by https://bun.com/install failure."
		fi
	fi
}

bun_install_tool() {
	print_log "act" "bun add -g $*"
	bun add -g "$@"
}

install_bun_tool() {
	bun_install_tool prettier
	bun_install_tool stylus
	bun_install_tool autocorrect-node
	bun_install_tool markdownlint-cli
}

install_fnm_and_config
install_node
install_node_tool

install_bun
install_bun_tool
