#!/bin/bash

set -euo pipefail

readonly SUDO="sudo"

# cur_dir="$(dirname "$(readlink -f "$0")")"
# dl_dir="$cur_dir/dl"

if [[ -z "${GITHUB:-}" ]]; then
	export GITHUB="https://gh-proxy.org/https://github.com"
fi
if [[ -z "${GITHUBRAW:-}" ]]; then
	export GITHUBRAW="https://gh-proxy.org/https://raw.githubusercontent.com"
fi

# $1 act|info|suc|fail
# $2 message
print_log() {
	case "$1" in
	fail)
		shift
		printf '\033[1;31m[Failure] %s\033[0m\n' "$*" # red
		;;
	suc)
		shift
		printf '\033[1;32m[Success] %s\033[0m\n' "$*" # green
		;;
	act)
		shift
		printf '\033[1;33m[Action] %s\033[0m\n' "$*" # yellow
		;;
	info)
		shift
		printf '\033[1;34m[Information] %s\033[0m\n' "$*" # blue
		;;
	*)
		shift
		printf '%s\n' "$*"
		;;
	esac
}

# example: apt_install_pkgs wget curl
apt_install_pkgs() {
	_ext=0
	for pkg in "$@"; do
		if dpkg -s "$pkg" &>/dev/null; then
			print_log "info" "package ${pkg} was installed ... skip"
		else
			print_log "act" "apt -qq -y install ${pkg}"
			if $SUDO apt -qq -y install "${pkg}"; then
				print_log "suc" "apt install ${pkg} success."
			else
				_ext=$?
				print_log "fail" "apt install ${pkg} failure."
			fi
		fi
	done
	return $_ext
}

# $1: target
# $2: soruce
# example: curl_get_file "$HOME/.gitconfig" "$GITHUBRAW/iceway/dotfiles/master/git/gitconfig"
curl_get_file() {
	_ext=0
	_tgt="${1:?missing arg 1 for target}"
	_src="${2:?missing arg 2 for source}"

	if [[ -f "${_tgt}" ]]; then
		print_log "info" "file ${_tgt} was existed ... skip"
	else
		print_log "act" "curl -fL --max-time 60 --create-dirs ${_src} -o ${_tgt}"
		if curl -fL --max-time 60 --create-dirs "${_src}" -o "${_tgt}"; then
			print_log "suc" "curl get ${_src} to ${_tgt} success."
		else
			_ext=$?
			print_log "fail" "curl get ${_src} to ${_tgt} failure."
		fi
	fi
	return $_ext
}

# $1: target dir
# $2: repo url
# example: git_clone_repo "$HOME/.tmux/plugins/tpm" "$GITHUB/tmux-plugins/tpm"
git_clone_repo() {
	_ext=0
	_tgt="${1:?missing arg 1 for target dir}"
	_src="${2:?missing arg 2 for repo url}"

	if git -C "${_tgt}" rev-parse --is-inside-work-tree; then
		print_log "info" "git repo ${_tgt} was existed ... skip"
	else
		print_log "act" "git clone ${_src} ${_tgt}"
		if git clone "${_src}" "${_tgt}"; then
			print_log "suc" "git clone ${_src} ${_tgt} success."
		else
			_ext=$?
			print_log "fail" "git clone ${_src} ${_tgt} failure."
		fi
	fi
	return $_ext
}
