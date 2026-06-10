#!/bin/bash

cur_dir="$(dirname "$(readlink -f "$0")")"
dl_dir="$cur_dir/dl"

source "$cur_dir/common-script.sh"

install_rustup_and_config() {
	_success=0

	if command -v rustup >/dev/null 2>&1; then
		print_log "info" "rustup is existed at $(which rustup) ... skip"
	else
		print_log "act" "install rust ..."
		export RUSTUP_DIST_SERVER="https://mirrors.aliyun.com/rustup"
		export RUSTUP_UPDATE_ROOT="https://mirrors.aliyun.com/rustup/rustup"
		if curl_get_file "$dl_dir/rustup.sh" https://rsproxy.cn/rustup-init.sh; then
			if sh "$dl_dir/rustup.sh" "-y"; then
				print_log "suc" "install rustup by https://rsproxy.cn/rustup-init.sh success."
				_success=1
			fi
			rm -f "$dl_dir/rustup.sh"
		fi

		if [[ $_success -eq 0 ]]; then
			if curl_get_file "$dl_dir/rustup.sh" https://mirrors.aliyun.com/repo/rust/rustup-init.sh; then
				if sh "$dl_dir/rustup.sh" "-y"; then
					print_log "suc" "install rustup by https://mirrors.aliyun.com/repo/rust/rustup-init.sh success."
					_success=1
				fi
				rm -f "$dl_dir/rustup.sh"
			fi
		fi

		if [[ $_success -eq 0 ]]; then
			if sh "$dl_dir/rustup-install.sh" "-y"; then
				# curl -LsSf https://rsproxy.cn/rustup-init.sh -o rustup-install.sh
				print_log "suc" "install rustup by $dl_dir/rustup-install.sh success."
				_success=1
			else
				print_log "fail" "install rustup failure."
			fi
		fi
	fi

	if ! grep -qE 'export RUSTUP_DIST_SERVER="?http.*' "$HOME/.zshrc" || ! grep -qE 'export RUSTUP_UPDATE_ROOT="?http.*' "$HOME/.zshrc"; then
		cat <<-EOF >>"$HOME/.zshrc"

			# rustup
			export RUSTUP_DIST_SERVER="https://mirrors.aliyun.com/rustup"
			export RUSTUP_UPDATE_ROOT="https://mirrors.aliyun.com/rustup/rustup"
		EOF
		source "$HOME/.zshrc" 2>/dev/null || true
	fi
	if [[ -f "$HOME/.cargo/env" ]]; then
		source "$HOME/.cargo/env" 2>/dev/null || true
		if ! grep -qE 'source "\$HOME/.cargo/env"' "$HOME/.zshrc"; then
			echo 'source "\$HOME/.cargo/env"' >>"$HOME/.zshrc"
		fi
	fi

	if ! grep -qE 'source.crates-io' ~/.cargo/config.toml; then
		print_log "act" "set mirror for creats.io"
		mkdir -p ~/.cargo/
		cat <<-EOF >~/.cargo/config.toml
			[source.crates-io]
			# 将默认的 crates.io 源替换为镜像源
			replace-with = 'aliyun'
			# 下面是各个镜像源的地址
			[source.aliyun]
			registry = "sparse+https://mirrors.aliyun.com/crates.io-index/"
		EOF
	fi
}

rustup_install_rust() {
	print_log "act" "rustup install $*"
	rustup install "$@"
}

install_rust() {
	rustup_install_rust 1.58.0
	rustup_install_rust stable
	rustup default 1.58.0
}

cargo_install_tool() {
	print_log "act" "cargo install $*"
	cargo install "$@"
}

cargo_binstall_tool() {
	print_log "act" "cargo binstall -y $*"
	cargo binstall -y "$@"
}

install_rust_tool() {
	cargo_install_tool "cargo-binstall"

	cargo_binstall_tool lsd        # 替代 exa、eza、ls
	cargo_binstall_tool bat        # 替代 cat
	cargo_binstall_tool ripgrep    # 替代 grep
	cargo_binstall_tool fd-find    # 替代 find
	cargo_binstall_tool sd         # sed 的现代化替代品，语法更易用（尤其正则分组和替换）。
	cargo_binstall_tool procs      # 彩色输出、按关键词过滤、多栏展示，显示进程信息比传统 ps 舒服得多。
	cargo_binstall_tool ngrv       # (Nagare Viewer)：一个用 Rust 编写的工具，是 pv 的现代替代品，性能好且界面美观
	cargo_binstall_tool hyperfine  # 替代 time， 用于命令行基准测试的统计工具，比time功能更强大
	cargo_binstall_tool git-delta  # 语法高亮、行号、差异内不同部分的标记
	cargo_binstall_tool difftastic # 替代 diff，理解代码结构（不是逐行文本比对），能显示移动的代码、树状差异等，尤其适合重构后的对比。
	cargo_binstall_tool du-dust    # 替代 du，按大小排序、树形展示，一目了然哪些目录占用空间。
	cargo_binstall_tool zoxide     # 替代 z，autojump 等工具
	cargo_binstall_tool hexyl      # 替代 hexdump / xxd
	cargo_binstall_tool zellij     # 替代 tmux
	cargo_binstall_tool miniserve  # 替代 python -m http.server
}

install_rustup_and_config
install_rust
install_rust_tool
