#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/functions.sh"

log() {
  _log "CI" "$1"
}

success() {
  _success "CI" "$1"
}

error() {
  _error "CI" "$1"
}

warn() {
  _warn "CI" "$1"
}

CONTAINER_NAME="dotfiles-ci-container"
CONTAINER_ID=""
DRY_RUN=false

ci_help() {
  echo "⚙️ ci.sh - コードフォーマットツール

[使用方法]
./ci.sh [オプション]

[説明]
dotfilesリポジトリ内のコードをフォーマットします。
既存のコンテナがあれば再利用し、なければ新規作成します。

[対象ファイル]
- Shell (.sh)      : shfmt
- Fish (.fish)     : fish_indent
- Lua (.lua)       : stylua
- JSON (.json)     : prettier
- PowerShell (.ps1): pwsh

[オプション]
--clean     既存のコンテナを削除して新規作成
--remove    既存のコンテナを削除して終了
--status    コンテナの状態を表示
-h, --help  このヘルプを表示

[例]
./ci.sh              フォーマット実行
./ci.sh --clean      コンテナを再作成してフォーマット
./ci.sh --remove     コンテナを削除
./ci.sh --status     コンテナの状態を確認"
}

is_running() {
  local container_id="$1"
  [ -n "$(docker ps -q --filter "id=$container_id" 2>/dev/null)" ]
}

container_id() {
  docker ps -aq --filter "name=$CONTAINER_NAME" 2>/dev/null | head -n1
}

status() {
  local existing_id
  existing_id=$(container_id)

  if [ -n "$existing_id" ]; then
    echo "┌──────────────────────────────────────────────────────────────"
    echo "│ コンテナ名：$CONTAINER_NAME"
    echo "│ コンテナ ID：${existing_id:0:12}"

    if is_running "$existing_id"; then
      echo "│ 状態：実行中 ✅"
    else
      echo "│ 状態：停止中 ⏸️"
    fi

    echo "└──────────────────────────────────────────────────────────────"
  else
    log "CI コンテナは存在しません"
    log "'./ci.sh' を実行して作成してください"
  fi
}

remove() {
  local existing_id
  existing_id=$(container_id)

  if [ -n "$existing_id" ]; then
    log "既存のコンテナを削除しています（ID：${existing_id:0:12}）..."
    docker stop "$existing_id" >/dev/null 2>&1 || true
    docker rm "$existing_id" >/dev/null 2>&1 || true
    success "既存のコンテナを削除しました"
  else
    log "既存のコンテナは見つかりませんでした"
  fi
}

ensure() {
  local container_id="$1"

  if ! is_running "$container_id"; then
    log "停止中のコンテナを起動しています..."
    docker start "$container_id" >/dev/null 2>&1
    sleep 1
  fi
}

create() {
  log "CI 用の Docker イメージをビルドしています..."
  if ! docker build \
    --build-arg LOCAL_UID="$(id -u)" \
    --build-arg LOCAL_GID="$(id -g)" \
    -f Dockerfile.ci \
    -t dotfiles-ci .; then
    error "Docker イメージのビルドに失敗しました"
    exit 1
  fi
  success "Docker イメージのビルドが完了しました"

  log "新しい CI コンテナを起動しています..."
  CONTAINER_ID=$(docker run -d \
    --name "$CONTAINER_NAME" \
    --label dotfiles-ci \
    -e LOCAL_UID="$(id -u)" \
    -e LOCAL_GID="$(id -g)" \
    -v "$(pwd):/workspaces" \
    --workdir /workspaces \
    dotfiles-ci \
    sleep 604800) # 7日間

  if [ -z "$CONTAINER_ID" ]; then
    error "コンテナの起動に失敗しました"
    exit 1
  fi

  success "CI コンテナを作成しました（ID：${CONTAINER_ID:0:12}）"
}

format() {
  log "Shell ファイル（.sh）をフォーマットしています..."
  docker exec --user "$(id -u):$(id -g)" "$CONTAINER_ID" find /workspaces -name "*.sh" -type f -exec shfmt -w {} \; || warn "Shell ファイルのフォーマット中に問題が発生しました"

  log "Fish ファイル（.fish）をフォーマットしています..."
  docker exec --user "$(id -u):$(id -g)" "$CONTAINER_ID" bash -c '
        for file in $(find /workspaces -name "*.fish" -type f); do
            fish_indent < "$file" > "${file}.tmp" && mv "${file}.tmp" "$file" || echo "警告：$file のフォーマットに失敗しました"
        done
    ' || warn "Fish ファイルのフォーマット中に問題が発生しました"

  log "Lua ファイル（.lua）をフォーマットしています..."
  docker exec --user "$(id -u):$(id -g)" "$CONTAINER_ID" bash -c '
        if [ -f /workspaces/stylua.toml ]; then
            find /workspaces -name "*.lua" -type f -exec stylua --config-path /workspaces/stylua.toml {} \;
        else
            find /workspaces -name "*.lua" -type f -exec stylua {} \;
        fi
    ' || warn "Lua ファイルのフォーマット中に問題が発生しました"

  log "JSON ファイル（.json）をフォーマットしています..."
  docker exec --user "$(id -u):$(id -g)" "$CONTAINER_ID" bash -c '
        find /workspaces -name "*.json" -type f -exec prettier --write {} \;
    ' || warn "JSON ファイルのフォーマット中に問題が発生しました"

  # タブをスペースに変換し、末尾の空白を削除し、連続する空行を1行にまとめる
  log "PowerShell ファイル（.ps1）をフォーマットしています..."
  docker exec --user "$(id -u):$(id -g)" "$CONTAINER_ID" bash -c '
        for file in $(find /workspaces -name "*.ps1" -type f); do
            pwsh -Command "
                try {
                    \$lines = Get-Content \"$file\"
                    \$result = @()

                    foreach (\$line in \$lines) {
                        \$cleaned = \$line -replace \"\\t\", \"    \"
                        \$cleaned = \$cleaned.TrimEnd()

                        if (\$cleaned -ne \"\") {
                            \$result += \$cleaned
                        } elseif (\$result.Count -gt 0 -and \$result[-1] -ne \"\") {
                            \$result += \"\"
                        }
                    }

                    while (\$result.Count -gt 1 -and \$result[-1] -eq \"\") {
                        \$result = \$result[0..(\$result.Count - 2)]
                    }

                    \$result | Set-Content \"$file\"
                    Write-Host \"フォーマット完了：$file\"
                } catch {
                    Write-Host \"警告：$file のフォーマットに失敗しました - \$_\"
                }
            "
        done
    ' || warn "PowerShell ファイルのフォーマット中に問題が発生しました"
}

main() {
  local do_clean=false

  while [[ $# -gt 0 ]]; do
    case $1 in
    --clean)
      do_clean=true
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
      ci_help
      exit 0
      ;;
    *)
      error "不明なオプション：$1"
      ci_help
      exit 1
      ;;
    esac
  done

  success "⚙️ ci.sh"

  if ! command -v docker >/dev/null 2>&1; then
    error "Docker が見つかりません。Docker をインストールしてください。"
    exit 1
  fi

  if ! docker info >/dev/null 2>&1; then
    error "Docker が起動していません。Docker を起動してください。"
    exit 1
  fi

  # --clean オプションが指定された場合は既存のコンテナを削除
  if [ "$do_clean" = true ]; then
    remove
  fi

  local existing_id
  existing_id=$(container_id)

  if [ -n "$existing_id" ]; then
    success "既存のコンテナを発見しました（ID：${existing_id:0:12}）"
    CONTAINER_ID="$existing_id"
    ensure "$existing_id"
  else
    create
  fi

  format

  success "✅ すべてのファイルの CI 処理が完了しました"
}

main "$@"
