#!/bin/bash

cur_dir="$(dirname "$(readlink -f "$0")")"
dl_dir="$cur_dir/dl"

source "$cur_dir/common-script.sh"

install_uv_and_config() {
	_success=0

	if hash uv 2>/dev/null; then
		print_log "info" "uv is existed at $(which uv) ... skip"
	else
		print_log "act" "install uv ..."
		export UV_INSTALLER_GHE_BASE_URL="${GITHUB}"
		if curl_get_file "$dl_dir/uv.sh" https://astral.sh/uv/install.sh; then
			if sh "$dl_dir/fnm.sh"; then
				print_log "suc" "install uv by https://astral.sh/uv/install.sh success."
				_success=1
			fi
			rm -f "$dl_dir/uv.sh"
		fi
		if [[ $_success -eq 0 ]]; then
			if sh "$dl_dir/uv-install.sh"; then
				# curl -LsSf https://astral.sh/uv/install.sh -o uv-install.sh
				print_log "suc" "install uv by $dl_dir/uv-install.sh success."
			else
				print_log "fail" "install uv failure."
			fi
		fi
	fi

	if ! grep -qE 'url' ~/.config/uv/uv.toml; then
		print_log "act" "set mirror for uv source."
		mkdir -p ~/.config/uv
		cat <<-EOF >~/.config/uv/uv.toml
			[[index]]
			url = "https://pypi.tuna.tsinghua.edu.cn/simple"
			default = true
		EOF
	fi
}

uv_install_python() {
	print_log "act" "uv python install $*"
	uv python install "$@"
}

install_python() {
	uv_install_python 3.10
	uv_install_python --default 3.12
	uv_install_python 3.14
}

uv_install_tool() {
	print_log "act" "uv tool install $*"
	uv tool install "$@"
}

install_python_tools() {
	uv_install_tool black
	uv_install_tool ruff         # Astral 出品（与 uv 同团队），用 Rust 编写的超快 Linter + Formatter。
	uv_install_tool clang-format # clang-format
	uv_install_tool cmakelang    # cmake-format, cmake-lint
	uv_install_tool httpie
}

install_uv_and_config
install_python
install_python_tools
