#!/bin/bash

cur_dir="$(dirname "$(readlink -f "$0")")"
dl_dir="$cur_dir/dl"

source "$cur_dir/common-script.sh"

install_g_and_config() {
	_success=0

	if command -v g >/dev/null 2>&1; then
		print_log "info" "g is existed at $(which g) ... skip"
	else
		print_log "act" "install g (go version manager) ..."
		mkdir -p "$HOME/.local/bin"
		export G_MIRROR="https://golang.google.cn/dl/"
		_g_url="${GITHUBRAW:-https://raw.githubusercontent.com}/voidint/g/master/install.sh"
		if curl_get_file "$dl_dir/g.sh" "$_g_url"; then
			sed -ri "s%https://github.com%${GITHUB}%" "$dl_dir/g.sh"
			if bash "$dl_dir/g.sh" "-y"; then
				print_log "suc" "install g by https://raw.githubusercontent.com/voidint/g/master/install.sh success."
				_success=1
			fi
			rm -f "$dl_dir/g.sh"
		fi

		if [[ $_success -eq 0 ]]; then
			if bash "$dl_dir/g-install.sh"; then
				print_log "suc" "install g by $dl_dir/g-install.sh success."
				_success=1
			else
				print_log "fail" "install g failure."
			fi
		fi
	fi

	if [[ -f "${HOME}/.g/env" ]]; then
		if [[ -n $(alias g 2>/dev/null) ]]; then unalias g; fi
		source "${HOME}/.g/env" 2>/dev/null || true
		if ! grep -qE 'source.*\.g/env' "$HOME/.zshrc"; then
			cat <<-EOF >>"$HOME/.zshrc"
				# g (go) env
				if [[ -n $(alias g 2>/dev/null) ]]; then unalias g; fi
				source "$HOME/.g/env"
			EOF
		fi
	fi
}

g_install_go() {
	print_log "act" "g install $*"
	g install "$@"
}

install_go() {
	g_install_go 1.22.0
	g_install_go 1.25.0
	g use 1.25.0

	go env -w GO111MODULE=on
	go env -w GOPROXY=https://goproxy.cn,direct
	go env -w GOSUMDB=off
}

go_install_tool() {
	print_log "act" "go install $*"
	go install "$@"
}

install_go_tool() {
	go_install_tool github.com/junegunn/fzf@latest
	go_install_tool mvdan.cc/sh/v3/cmd/shfmt@latest
	go_install_tool github.com/tomwright/dasel/v2/cmd/dasel@latest
}

install_g_and_config
install_go
install_go_tool
