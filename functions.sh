#!/bin/bash

set -euo pipefail

readonly MAGENTA='\033[35m'
readonly GREEN='\033[32m'
readonly RED='\033[31m'
readonly YELLOW='\033[33m'
readonly BLUE='\033[36m'
readonly NC='\033[0m'

_log() {
  echo -e "${MAGENTA}[$1]${NC} $2"
}

_success() {
  echo -e "${GREEN}[$1]${NC} $2"
}

_error() {
  echo -e "${RED}[$1]${NC} $2"
  exit 1
}

_warn() {
  echo -e "${YELLOW}[$1]${NC} $2"
}

load_environment() {
  # Git のグローバル設定からユーザー情報を取得
  GIT_USER_NAME=${GIT_USER_NAME:-"$(git config --global user.name 2>/dev/null || echo '')"}
  GIT_USER_EMAIL=${GIT_USER_EMAIL:-"$(git config --global user.email 2>/dev/null || echo '')"}
  WINDOWS_USERNAME=${WINDOWS_USERNAME:-"$(whoami)"}
  SSH_KEY_NAME=${SSH_KEY_NAME:-"$GIT_USER_NAME"}

  # Git ユーザー情報が未設定の場合は警告を表示
  if [[ -z "$GIT_USER_NAME" || -z "$GIT_USER_EMAIL" ]]; then
    _warn "FUNCTIONS" "Git ユーザー情報が見つかりません。一部の設定が正しく動作しない可能性があります。"
    _log "FUNCTIONS" "'git config --global user.name \"名前\"' と 'git config --global user.email \"メール\"' を実行してください。"
  fi
}

expand_placeholder() {
  local source_file="$1"
  local dest_file="$2"

  if [ ! -f "$source_file" ]; then
    _warn "FUNCTIONS" "$source_file が見つかりません"
    return 1
  fi

  _log "FUNCTIONS" "プレースホルダーを展開しています： $source_file → $dest_file"

  local temp_file=$(mktemp)
  cp "$source_file" "$temp_file"

  # 各プレースホルダーを対応する環境変数の値で置換
  sed -i "s|{{GIT_USER_NAME}}|$GIT_USER_NAME|g" "$temp_file"
  sed -i "s|{{GIT_USER_EMAIL}}|$GIT_USER_EMAIL|g" "$temp_file"
  sed -i "s|{{HOME}}|$HOME|g" "$temp_file"
  sed -i "s|{{WINDOWS_USERNAME}}|$WINDOWS_USERNAME|g" "$temp_file"
  sed -i "s|{{SSH_KEY_NAME}}|$SSH_KEY_NAME|g" "$temp_file"

  cp "$temp_file" "$dest_file" && rm "$temp_file"
}
