#!/bin/bash

cur_dir="$(dirname "$(readlink -f "$0")")"
# dl_dir="$cur_dir/dl"

source "$cur_dir/common-script.sh"

install_base_pkgs_and_config_apt_mirror() {
	apt_install_pkgs grep
	apt_install_pkgs sed
	apt_install_pkgs gawk

	_file="/etc/apt/sources.list"
	_official_url="http://.*archive.ubuntu.com"
	_mirror_url="http://mirror.sjtu.edu.cn"
	if ! grep -qE "${_mirror_url}" "${_file}"; then
		$SUDO sed -ri -e "s#${_official_url}#${_mirror_url}#g" "${_file}"
		$SUDO apt -qq update
	fi
}

install_base_pkgs() {
	apt_install_pkgs file
	apt_install_pkgs diffutils
	apt_install_pkgs findutils
	apt_install_pkgs dos2unix

	apt_install_pkgs wget
	apt_install_pkgs curl
	apt_install_pkgs jq

	apt_install_pkgs tar
	apt_install_pkgs gzip
	apt_install_pkgs bzip2
	apt_install_pkgs xz-utils
	apt_install_pkgs unzip
	apt_install_pkgs unrar
	apt_install_pkgs p7zip-full
	apt_install_pkgs lz4
	apt_install_pkgs zstd

	apt_install_pkgs tree
	apt_install_pkgs lftp
	apt_install_pkgs shfmt
}

install_system_pkgs() {
	apt_install_pkgs iputils-ping
	apt_install_pkgs net-tools
	apt_install_pkgs iproute2
	apt_install_pkgs lsof
	apt_install_pkgs sysstat
	apt_install_pkgs psmisc
	apt_install_pkgs htop
	apt_install_pkgs lshw
}

install_other_pkgs() {
	apt_install_pkgs ffmpeg
	apt_install_pkgs figlet

	apt_install_pkgs "fonts-noto-cjk"
	apt_install_pkgs "fonts-arphic-ukai"
}

install_common_tool_and_config() {
	### git
	apt_install_pkgs git
	apt_install_pkgs tig
	curl_get_file "$HOME/.gitconfig" "$GITHUBRAW/iceway/dotfiles/master/git/gitconfig"
	git config --global "url.$GITHUB.insteadOf" "https://github.com"

	### vim
	apt_install_pkgs vim
	curl_get_file "$HOME/.vim/autoload/plug.vim" "$GITHUBRAW/junegunn/vim-plug/master/plug.vim"
	curl_get_file "$HOME/.vimrc" "$GITHUBRAW/iceway/dotfiles/master/vim/vimrc"

	### tmux
	apt_install_pkgs tmux
	curl_get_file "$HOME/.tmux.conf" "$GITHUBRAW/iceway/dotfiles/master/tmux/tmux.conf"
	mkdir -p "$HOME/.tmux/plugins"
	git_clone_repo "$HOME/.tmux/plugins/tpm" "$GITHUB/tmux-plugins/tpm"
	git_clone_repo "$HOME/.tmux/plugins/tmux-prefix-highlight" "$GITHUB/tmux-plugins/tmux-prefix-highlight"
	git_clone_repo "$HOME/.tmux/plugins/tmux-resurrect" "$GITHUB/tmux-plugins/tmux-resurrect"
}

curl_get_file "$HOME/.bashrc" "$GITHUBRAW/iceway/dotfiles/master/bash/bashrc"

install_zsh_and_config() {
	### zsh
	apt_install_pkgs zsh

	# oh-my-zsh
	if ! git -C "$HOME/.oh-my-zsh" rev-parse --is-inside-work-tree; then
		curl -fsSL https://git.sjtu.edu.cn/sjtug/ohmyzsh/-/raw/master/tools/install.sh | REMOTE=https://git.sjtu.edu.cn/sjtug/ohmyzsh.git bash -x
	fi
	mkdir -p "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins"
	git_clone_repo "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions" "$GITHUB/zsh-users/zsh-autosuggestions"
	git_clone_repo "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting" "$GITHUB/zsh-users/zsh-syntax-highlighting"
	git_clone_repo "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-history-substring-search" "$GITHUB/zsh-users/zsh-history-substring-search"

	if grep -qE '^ZSH_THEME="\w+"' "$HOME/.zshrc"; then
		sed -ri -e 's%^ZSH_THEME="\w+"%ZSH_THEME="ys"%' "$HOME/.zshrc"
	else
		sed -ri -e 's%^#\s*ZSH_THEME="\w+"%ZSH_THEME="ys"%' "$HOME/.zshrc"
	fi
	for plug in tig z colored-man-pages command-not-found zsh-autosuggestions zsh-syntax-highlighting zsh-history-substring-search; do
		if grep -E '^plugins=\((.*)\)' "$HOME/.zshrc" && ! grep -qE "\b${plug}\b" "$HOME/.zshrc"; then
			sed -ri -e "s%^plugins=\((.*)\)%(\1 ${plug})%" "$HOME/.zshrc"
		fi
	done
	if ! grep -qE 'history-substring-search-up' "$HOME/.zshrc"; then
		cat <<EOF >>"$HOME/.zshrc"
bindkey "\$terminfo[kcuu1]" history-substring-search-up
bindkey "\$terminfo[kcud1]" history-substring-search-down
bindkey -M emacs '^P' history-substring-search-up
bindkey -M emacs '^N' history-substring-search-down
EOF
	fi
	if ! grep -qE "^$USER"'.*/usr/bin/zsh$' /etc/passwd; then
		chsh -s "$(which zsh)" "$USER"
	fi
}

install_base_pkgs_and_config_apt_mirror
install_base_pkgs
install_system_pkgs
install_other_pkgs
install_common_tool_and_config
install_zsh_and_config
