#!/bin/bash

cur_dir="$(dirname "$(readlink -f "$0")")"
# dl_dir="$cur_dir/dl"

source "$cur_dir/common-script.sh"

install_bun() {
	if hash bun 2>/dev/null; then
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

install_opencode() {
	if hash oepncode 2>/dev/null; then
		print_log "info" "opencode is existed at $(which opencode) ... skip"
	else
		print_log "act" "install opencode ..."
		if bun install -g opencode-ai; then
			print_log "suc" "install opencode via bun success."
		else
			print_log "fail" "install opencode via bun failure."
		fi
		# bunx oh-my-opencode install --no-tui --claude=no --openai=no --gemini=no --copilot=no --opencode-zen=yes
	fi

	opencode_repo_dir="$HOME/.config/opencode/repos"
	opencode_skill_dir="$HOME/.config/opencode/skills"
	mkdir -p "$opencode_repo_dir"
	mkdir -p "$opencode_skill_dir"
	git_clone_repo "$opencode_repo_dir/anthropics-skills.git" "$GITHUB/anthropics/skills"
	ln -sf "$opencode_repo_dir/anthropics-skills.git/skills" "$opencode_skill_dir/anthropics-skills"

	if ! grep -qE 'tarquinen/opencode-dcp' "$HOME/.config/opencode/opencode.json"; then
		jq '.plugin += ["@tarquinen/opencode-dcp@latest"]' "$HOME/.config/opencode/opencode.json"
	fi
	if ! grep -qE 'superpowers' "$HOME/.config/opencode/opencode.json"; then
		jq '.plugin += ["superpowers@git+https://github.com/obra/superpowers.git"]' "$HOME/.config/opencode/opencode.json"
	fi
	if ! grep -qE 'integrate.api.nvidia.com' "$HOME/.config/opencode/opencode.json"; then
		cat <<-EOF
			"provider": {
				"my-nim": {
					"npm": "@ai-sdk/openai-compatible",
					"options": {
					"baseURL": "https://integrate.api.nvidia.com/v1",
					"thinking": {
						"type": "enabled"
					}
					},
					"models": {
					"glm-5.1": {
						"id": "z-ai/glm-5.1"
					},
					"kimi-2.6": {
						"id": "moonshotai/kimi-k2.6"
					},
					"minimax-2.7": {
						"id": "minimaxai/minimax-m2.7"
					},
					"gemma-4-31b": {
						"id": "google/gemma-4-31b-it"
					},
					"qwen3.5-122b-a10b": {
						"id": "qwen/qwen3.5-122b-a10b"
					}
					}
				}
			}
		EOF
	fi
}

install_bun
install_opencode
