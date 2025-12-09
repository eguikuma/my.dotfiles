#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/functions.sh"

log() {
  _log "SANDBOX" "$1"
}

success() {
  _success "SANDBOX" "$1"
}

error() {
  _error "SANDBOX" "$1"
}

warn() {
  _warn "SANDBOX" "$1"
}

CONTAINER_NAME="dotfiles-sandbox-container"
CONTAINER_ID=""

sandbox_help() {
  echo "🏖️ sandbox.sh - サンドボックス環境

[使用方法]
./sandbox.sh [オプション]

[説明]
dotfilesのテスト用サンドボックス環境をDockerで作成・管理します。
既存のコンテナがあれば再利用し、なければ新規作成します。

[オプション]
--clean     既存のコンテナを削除して新規作成
--remove    既存のコンテナを削除して終了
--status    コンテナの状態を表示
-h, --help  このヘルプを表示

[例]
./sandbox.sh              既存コンテナに接続（なければ新規作成）
./sandbox.sh --clean      既存コンテナを削除して新規作成
./sandbox.sh --remove     既存コンテナを削除
./sandbox.sh --status     コンテナの状態を確認"
}

is_running() {
  local id="$1"
  [ -n "$(docker ps -q --filter "id=$id" 2>/dev/null)" ]
}

container_id() {
  docker ps -aq --filter "name=$CONTAINER_NAME" 2>/dev/null | head -n1
}

status() {
  local id
  id=$(container_id)

  if [ -n "$id" ]; then
    echo "┌──────────────────────────────────────────────────────────────"
    echo "│ コンテナ名：$CONTAINER_NAME"
    echo "│ コンテナ ID：${id:0:12}"

    if is_running "$id"; then
      echo "│ 状態：実行中 ✅"
    else
      echo "│ 状態：停止中 ⏸️"
    fi

    echo "│ 接続：docker exec -it ${id:0:12} bash"
    echo "└──────────────────────────────────────────────────────────────"
  else
    log "サンドボックスコンテナは存在しません"
    log "'./sandbox.sh' を実行して作成してください"
  fi
}

remove() {
  local id
  id=$(container_id)

  if [ -n "$id" ]; then
    log "既存のコンテナを削除しています（ID：${id:0:12}）..."
    docker stop "$id" >/dev/null 2>&1 || true
    docker rm "$id" >/dev/null 2>&1 || true
    success "既存のコンテナを削除しました"
  else
    log "既存のコンテナは見つかりませんでした"
  fi
}

create() {
  log "サンドボックス用の Docker イメージをビルドしています..."
  if ! docker build -f Dockerfile.sandbox -t dotfiles-sandbox .; then
    error "Docker イメージのビルドに失敗しました"
    exit 1
  fi
  success "Docker イメージのビルドが完了しました"

  log "新しいサンドボックスコンテナを起動しています..."
  CONTAINER_ID=$(docker run -d \
    --name "$CONTAINER_NAME" \
    --label dotfiles-sandbox \
    -v "$(pwd):/home/sandbox/workspaces/github.com/sandbox/my.dotfiles" \
    --workdir /home/sandbox \
    dotfiles-sandbox \
    sleep 604800) # 7日間

  if [ -z "$CONTAINER_ID" ]; then
    error "コンテナの起動に失敗しました"
    exit 1
  fi

  success "サンドボックスコンテナを作成しました（ID：${CONTAINER_ID:0:12}）"

  sleep 3

  log "setup.sh を実行しています..."

  if timeout 2400 docker exec "$CONTAINER_ID" bash -c "cd workspaces/github.com/sandbox/my.dotfiles && ./setup.sh" 2>&1; then
    success "✅ setup.sh が完了しました"
  else
    local setup_exit_code=$?
    if [ $setup_exit_code -eq 124 ]; then
      error "タイムアウト（40分）"
    else
      error "実行エラー（終了コード：$setup_exit_code）"
    fi
    log "デバッグ用シェルをコンテナ内で起動しています..."
  fi
}

attach() {
  local id="$1"

  if ! is_running "$id"; then
    log "停止中のコンテナを起動しています..."
    docker start "$id" >/dev/null 2>&1
    sleep 1
  fi

  success "コンテナに接続しています（ID：${id:0:12}）"
  echo "┌──────────────────────────────────────────────────────────────"
  echo "│ ヒント：'fish' で Fish shell を起動"
  echo "│ ヒント：'exit' で退出（コンテナは実行し続けます）"
  echo "│ ヒント：'./sync.sh' で dotfiles の変更を適用"
  echo "└──────────────────────────────────────────────────────────────"

  docker exec -it "$id" bash
}

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --clean)
      remove
      shift
      ;;
    --remove)
      remove
      exit 0
      ;;
    --status)
      status
      exit 0
      ;;
    -h | --help)
      sandbox_help
      exit 0
      ;;
    *)
      error "不明なオプション：$1"
      sandbox_help
      exit 1
      ;;
    esac
  done

  success "🏖️ sandbox.sh"

  if ! command -v docker >/dev/null 2>&1; then
    error "Docker が見つかりません。Docker をインストールしてください。"
    exit 1
  fi

  if ! docker info >/dev/null 2>&1; then
    error "Docker が起動していません。Docker を起動してください。"
    exit 1
  fi

  local id
  id=$(container_id)

  if [ -n "$id" ]; then
    success "既存のコンテナを発見しました（ID：${id:0:12}）"
    CONTAINER_ID="$id"
    attach "$id"
  else
    create
    attach "$CONTAINER_ID"
  fi

  echo
  warn "コンテナはバックグラウンドで実行し続けています"
  warn "  再接続：docker exec -it ${CONTAINER_ID:0:12} bash"
  warn "  状態確認：./sandbox.sh --status"
  warn "  削除：./sandbox.sh --remove"
}

main "$@"
