#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/functions.sh"

SANDBOX=${SANDBOX:-0}
SYNC_ONLY=false
SKIP_CONFIRM=false

log() {
  _log "SETUP" "$1"
}

success() {
  _success "SETUP" "$1"
}

warn() {
  _warn "SETUP" "$1"
}

error() {
  _error "SETUP" "$1"
}

CURRENT_STEP=0

step() {
  CURRENT_STEP=$((CURRENT_STEP + 1))
  echo -e "${BLUE}[$CURRENT_STEP/$TOTAL_STEPS]${NC} $1"
}

help() {
  echo "🚀 setup.sh - dotfiles環境セットアップツール

[使用方法]
./setup.sh [オプション]

[説明]
WSL2/Linux環境にdotfilesをセットアップします。
二度目以降の実行では、既にインストール済みのツールはスキップされます。

[オプション]
--sync        設定ファイルのみ同期（ツールインストールをスキップ）
-y, --yes     すべての確認プロンプトをスキップ
-h, --help    このヘルプを表示

[例]
./setup.sh            フルセットアップ（初回）
./setup.sh --sync     設定ファイルのみ同期
./setup.sh --sync -y  確認なしで設定を同期"
}

# 上書き確認が必要な重要ファイルのリスト
CRITICAL_FILES=(
  "$HOME/.gitconfig"
  "$HOME/.config/fish/config.fish"
  "$HOME/.ssh/config"
  "$HOME/.ssh/github/config"
)

is_critical() {
  local file="$1"
  for critical in "${CRITICAL_FILES[@]}"; do
    if [ "$file" == "$critical" ]; then
      return 0
    fi
  done
  return 1
}

is_installed_command() {
  command -v "$1" &>/dev/null
}

is_brew_installed() {
  if is_installed_command brew; then
    brew list "$1" &>/dev/null
    return $?
  fi
  return 1
}

normalized_dotfiles_path() {
  # dotfilesディレクトリから直接実行されているかを確認
  if [ -f "./fish/config.fish" ]; then
    echo "$(pwd)"
  else
    # ghq clone後に実行されている場合は ghq root から取得
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)" 2>/dev/null || true
    echo "$(ghq root)/github.com/$GITHUB_USERNAME/my.dotfiles"
  fi
}

unmanaged_apt_packages() {
  # apt でインストールしたパッケージのうち、管理対象外のものを警告
  local dotfiles_path
  dotfiles_path=$(normalized_dotfiles_path)
  local bootstrap_file="$dotfiles_path/apt/bootstrap_packages"
  local whitelist_file="$dotfiles_path/apt/whitelist_packages"

  if [ -f "$bootstrap_file" ] && [ -f "$whitelist_file" ]; then
    # インストール済みパッケージと管理リストを比較
    local installed whitelist unmanaged
    installed=$(apt-mark showmanual 2>/dev/null | sort)
    whitelist=$(cat "$whitelist_file" "$bootstrap_file" 2>/dev/null | grep -v '^#' | grep -v '^$' | sort -u)
    unmanaged=$(comm -23 <(echo "$installed") <(echo "$whitelist"))

    if [ -n "$unmanaged" ]; then
      local brew_packages
      brew_packages=$(brew list --formula 2>/dev/null | sort)

      warn "以下の apt パッケージは setup.sh で管理されていません："
      for pkg in $unmanaged; do
        if echo "$brew_packages" | grep -qx "$pkg"; then
          echo "  $pkg（削除可能）"
        else
          echo "  $pkg"
        fi
      done
      log "削除する場合：sudo apt remove <パッケージ名>"
    fi
  fi
}

overwrite() {
  local file="$1"

  # -y オプションで確認スキップが有効な場合は常に上書き
  if [ "$SKIP_CONFIRM" == "true" ]; then
    return 0
  fi

  # ファイルが存在しない場合は新規作成として許可
  if [ ! -f "$file" ]; then
    return 0
  fi

  # 重要ファイル以外は確認なしで上書き
  if ! is_critical "$file"; then
    return 0
  fi

  warn "ファイルが既に存在します：$file"
  read -r -p "上書きしますか？（y/N/a=すべて上書き/s=スキップ）> " response
  case "$response" in
  [Yy]) return 0 ;;
  [Aa])
    SKIP_CONFIRM=true
    return 0
    ;;
  [Ss] | [Nn] | "") return 1 ;;
  *) return 1 ;;
  esac
}

prepare_wsl2() {
  step "WSL2 環境の準備を開始します。"

  if ! grep -q Microsoft /proc/version 2>/dev/null && [ ! -f /.dockerenv ]; then
    warn "このスクリプトは WSL2 環境向けに最適化されています。"
    log "代替環境（Docker コンテナまたはネイティブ Linux）で実行中です。"
  else
    log "WSL2 または Docker コンテナ環境で実行中です。"
  fi

  success "WSL2 環境の準備が完了しました。"
}

prepare_user() {
  step "ユーザー情報の準備を開始します。"

  load_environment

  if [[ -z "$GIT_USER_NAME" ]]; then
    echo -n "Git ユーザー名を入力してください："
    read -r GIT_USER_NAME
  fi

  if [[ -z "$GIT_USER_EMAIL" ]]; then
    echo -n "Git メールアドレスを入力してください："
    read -r GIT_USER_EMAIL
  fi

  GITHUB_SSH_KEY=${GITHUB_SSH_KEY:-""}

  # リモート URL から GitHub ユーザー名を自動検出
  # github.com: または github.com/ の両方のパターン
  if [ -z "${GITHUB_USERNAME:-}" ] && [ -d ".git" ]; then
    GITHUB_USERNAME=$(git remote get-url origin 2>/dev/null | sed -n 's|.*github.com[:/]\([^/]*\)/.*|\1|p')
    [ -n "$GITHUB_USERNAME" ] && log "リモート URL から GitHub ユーザー名を自動検出しました：$GITHUB_USERNAME"
  fi

  if [[ -z "$GITHUB_USERNAME" ]]; then
    echo -n "GitHub ユーザー名を入力してください："
    read -r GITHUB_USERNAME
  fi

  if [[ -z "$GITHUB_USERNAME" ]]; then
    error "GitHub ユーザー名は必須です。"
  fi

  SSH_KEY_NAME=${SSH_KEY_NAME:-"$GIT_USER_NAME"}

  if [[ -z "$GIT_USER_NAME" || -z "$GIT_USER_EMAIL" ]]; then
    error "Git ユーザー名とメールアドレスは必須です。"
  fi

  log "設定内容："
  log "  Git ユーザー名：$GIT_USER_NAME"
  log "  Git メールアドレス：$GIT_USER_EMAIL"
  log "  Windows ユーザー名：$WINDOWS_USERNAME"
  log "  GitHub ユーザー名：$GITHUB_USERNAME"
  log "  SSH キー名：$SSH_KEY_NAME"
  log "  GitHub SSH キー：${GITHUB_SSH_KEY:-未指定}"

  success "ユーザー情報の準備が完了しました。"
}

configure_git() {
  step "Git グローバル設定を開始します。"

  log "Git グローバル設定にユーザー情報を適用しています..."

  git config --global user.name "$GIT_USER_NAME"
  git config --global user.email "$GIT_USER_EMAIL"

  git config --global core.editor "nvim"

  log "Git 設定を適用しました："
  log "  - ユーザー名：$GIT_USER_NAME"
  log "  - メールアドレス：$GIT_USER_EMAIL"
  log "  - デフォルトエディタ：Neovim"

  success "Git グローバル設定が完了しました。"
  log "ヒント：'git config --list' で設定を確認できます。"
}

configure_ghq() {
  # ghq の設定（インストールは install_brew_packages で実行済み）
  step "ghq の設定を開始します。"

  log "ghq のルートディレクトリを設定しています..."
  git config --global ghq.root "~/workspaces"
  mkdir -p ~/workspaces

  success "ghq の設定が完了しました。"
  log "使い方：'ghq get https://github.com/user/repo' でリポジトリをクローン"
  log "使い方：'ghq list' で管理中のリポジトリ一覧を表示"
}

configure_dotfiles() {
  step "dotfiles の設定を開始します。"

  local dotfiles_path
  dotfiles_path=$(normalized_dotfiles_path)

  if [ ! -d "$dotfiles_path" ]; then
    error "dotfiles リポジトリが見つかりません：$dotfiles_path"
  fi

  log "dotfiles ディレクトリに移動します：$dotfiles_path"
  cd "$dotfiles_path"

  log "Fish shell の設定をセットアップしています..."
  log "  - メイン設定：config.fish（環境変数、エイリアス、パス設定）"
  log "  - 初期化設定：conf.d/（起動時に自動実行）"
  log "  - カスタム関数：functions/（ユーティリティコマンド）"
  mkdir -p ~/.config/fish/conf.d ~/.config/fish/functions

  if [ -f "fish/config.fish" ]; then
    if overwrite ~/.config/fish/config.fish; then
      expand_placeholder "fish/config.fish" ~/.config/fish/config.fish || { error "Fish 設定ファイルの処理に失敗しました"; }
      log "更新しました：~/.config/fish/config.fish"
    else
      log "スキップしました：~/.config/fish/config.fish"
    fi
  else
    warn "fish/config.fish が見つかりません"
  fi

  if [ -d "fish/conf.d" ] && [ "$(ls -A fish/conf.d 2>/dev/null)" ]; then
    log "Fish conf.d ファイルを同期しています..."
    cp fish/conf.d/* ~/.config/fish/conf.d/ || log "一部の Fish conf.d ファイルのコピーをスキップしました"
  fi

  if [ -d "fish/functions" ] && [ "$(ls -A fish/functions 2>/dev/null)" ]; then
    log "Fish 関数を同期しています..."
    cp fish/functions/* ~/.config/fish/functions/ || log "一部の Fish 関数ファイルのコピーをスキップしました"
  fi

  log "Git グローバル設定をセットアップしています..."
  log "  - メイン設定：.gitconfig（エイリアス、デフォルトブランチなど）"

  if [ -f "git/.gitconfig" ]; then
    if overwrite ~/.gitconfig; then
      expand_placeholder "git/.gitconfig" ~/.gitconfig || { error "Git 設定ファイルの処理に失敗しました"; }
      log "更新しました：~/.gitconfig"
    else
      log "スキップしました：~/.gitconfig"
    fi
  else
    warn "git/.gitconfig が見つかりません"
  fi

  log "Neovim エディタの設定をセットアップしています..."
  log "  - メイン設定：init.lua（基本的なエディタ動作設定）"
  log "  - プラグイン：plugins.lua（LSP、ファイルエクスプローラーなど）"
  mkdir -p ~/.config/nvim/lua

  if [ -f "nvim/init.lua" ]; then
    cp nvim/init.lua ~/.config/nvim/ || { error "Neovim 設定ファイルのコピーに失敗しました"; }
  else
    warn "nvim/init.lua が見つかりません"
  fi

  if [ -f "nvim/lua/plugins.lua" ]; then
    cp nvim/lua/plugins.lua ~/.config/nvim/lua/ || log "Neovim プラグイン設定のコピーをスキップしました"
  fi

  log "SSH 接続設定をセットアップしています..."
  log "  - メイン設定：config（ホスト別接続設定）"
  log "  - GitHub 設定：github/config（GitHub サーバー用）"
  mkdir -p ~/.ssh/github

  if [ -f "ssh/config" ]; then
    if overwrite ~/.ssh/config; then
      cp ssh/config ~/.ssh/ || { error "SSH 設定ファイルのコピーに失敗しました"; }
      log "更新しました：~/.ssh/config"
    else
      log "スキップしました：~/.ssh/config"
    fi
  else
    warn "ssh/config が見つかりません"
  fi

  if [ -f "ssh/github/config" ]; then
    if overwrite ~/.ssh/github/config; then
      expand_placeholder "ssh/github/config" ~/.ssh/github/config || log "SSH GitHub 設定の処理に失敗しました"
      log "更新しました：~/.ssh/github/config"
    else
      log "スキップしました：~/.ssh/github/config"
    fi
  else
    warn "ssh/github/config が見つかりません"
  fi

  log "環境固有の設定を調整しています..."

  # ユーザー名に応じて workspaces パスを調整
  local username=$(whoami)
  if [ -f ~/.config/fish/functions/github.fish ]; then
    log "  - ユーザー名 '$username' 用に workspaces パスを調整"
    sed -i "s|/home/[^/]*/workspaces|/home/$username/workspaces|g" ~/.config/fish/functions/github.fish
  fi

  log "セキュリティのため SSH 設定ファイルの権限を調整しています..."
  chmod 600 ~/.ssh/config ~/.ssh/*/config 2>/dev/null || true

  success "dotfiles の設定が完了しました。"
  log "ヒント：Fish shell を起動して新しい設定を適用してください。"
}

configure_default_shell() {
  step "デフォルトシェルの設定を開始します。"

  local brew_fish="/home/linuxbrew/.linuxbrew/bin/fish"

  # Homebrew 版 fish が存在するか確認
  if [ ! -x "$brew_fish" ]; then
    warn "Homebrew 版 fish が見つかりません。スキップします。"
    return
  fi

  # /etc/shells に Homebrew 版 fish を追加
  if ! grep -q "$brew_fish" /etc/shells 2>/dev/null; then
    log "Homebrew 版 fish を /etc/shells に追加しています..."
    echo "$brew_fish" | sudo tee -a /etc/shells >/dev/null
  fi

  # 現在のデフォルトシェルを確認
  local current_shell
  current_shell=$(getent passwd "$(whoami)" | cut -d: -f7)

  if [ "$current_shell" = "$brew_fish" ]; then
    log "デフォルトシェルは既に Homebrew 版 fish です。スキップします。"
  else
    log "デフォルトシェルを Homebrew 版 fish に変更しています..."
    sudo chsh -s "$brew_fish" "$(whoami)"
    success "デフォルトシェルを変更しました：$brew_fish"
  fi

  success "デフォルトシェルの設定が完了しました。"
}

install_apt_tools() {
  step "基本的な開発ツールとライブラリのインストールを開始します。"

  log "システムパッケージリストを更新しています..."
  sudo apt-get update

  local dotfiles_path
  dotfiles_path=$(normalized_dotfiles_path)
  local bootstrap_file="$dotfiles_path/apt/bootstrap_packages"

  # 未インストールのパッケージのみをリストアップ
  local packages_to_install=""

  if [ -f "$bootstrap_file" ]; then
    while IFS= read -r pkg || [ -n "$pkg" ]; do
      # コメント行と空行をスキップ
      [[ -z "$pkg" || "$pkg" =~ ^# ]] && continue

      if ! dpkg -s "$pkg" &>/dev/null; then
        packages_to_install="$packages_to_install $pkg"
      else
        log "パッケージ '$pkg' は既にインストール済みです。スキップします。"
      fi
    done <"$bootstrap_file"
  else
    warn "bootstrap_packages ファイルが見つかりません：$bootstrap_file"
    log "デフォルトで build-essential をインストールします..."
    packages_to_install="build-essential"
  fi

  if [ -n "$packages_to_install" ]; then
    log "パッケージをインストールしています：$packages_to_install"
    sudo apt-get install -y $packages_to_install
  else
    log "すべての基本パッケージはインストール済みです。"
  fi

  # Homebrew をインストール
  if ! is_installed_command brew; then
    log "Homebrew パッケージマネージャーをインストールしています..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    success "Homebrew のインストールが完了しました。"
  else
    log "Homebrew は既にインストール済みです。スキップします。"
  fi

  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"

  # bash 用 Homebrew パスの設定
  if [ -f ~/.bashrc ]; then
    if ! grep -q 'linuxbrew' ~/.bashrc 2>/dev/null; then
      log "bash でも Homebrew を使えるよう設定しています..."
      cat >>~/.bashrc <<'EOF'
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
export HOMEBREW_CURL_PATH="/home/linuxbrew/.linuxbrew/bin/curl"
EOF
    fi
  fi

  success "基本的な開発ツールとライブラリのインストールが完了しました。"
}

install_fonts() {
  step "フォントのインストールを開始します。"

  # 既にインストール済みの場合はスキップ
  if ls ~/.local/share/fonts/JetBrains*.ttf >/dev/null 2>&1; then
    log "JetBrains Mono Nerd Font は既にインストール済みです。スキップします。"
    success "フォントのインストールが完了しました。"
    return
  fi

  log "フォントのインストール先：~/.local/share/fonts/"
  mkdir -p ~/.local/share/fonts

  log "GitHub から JetBrains Mono Nerd Font v3.4.0 をダウンロードしています..."

  local original_dir="$(pwd)"
  cd ~

  if [ ! -f "JetBrainsMono.zip" ]; then
    curl -fLo "JetBrainsMono.zip" \
      https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/JetBrainsMono.zip
    log "フォントアーカイブのダウンロードが完了しました。"
  else
    log "フォントアーカイブが既に存在します。再利用します。"
  fi

  log "フォントファイルを展開してインストールしています..."
  unzip -o JetBrainsMono.zip -d JetBrainsMono
  cp JetBrainsMono/*.ttf ~/.local/share/fonts/
  fc-cache -fv
  rm -rf JetBrainsMono JetBrainsMono.zip

  log "フォントのインストール状況を確認しています..."
  # キャッシュ更新直後だと検出に失敗することがあるため、ファイルの存在確認を使用
  if ls ~/.local/share/fonts/JetBrains*.ttf >/dev/null 2>&1; then
    success "フォントのインストールが完了しました。"
    log "次に、Windows にも同じフォントをインストールし、Windows Terminal で設定してください。"
  else
    warn "フォントの登録が確認できません。手動で再インストールしてください。"
  fi

  cd "$original_dir"
}

install_dotfiles() {
  step "dotfiles のクローンを開始します。"

  local dotfiles_path="$(ghq root)/github.com/$GITHUB_USERNAME/my.dotfiles"

  # サンドボックス環境の場合はスキップ
  if [[ "${SANDBOX:-0}" == "1" ]]; then
    success "サンドボックス環境で実行中です。"
    log "パス：$dotfiles_path"
    return
  fi

  # 既に存在する場合は再利用
  if [ -d "$dotfiles_path" ]; then
    log "my.dotfiles が既に存在します：$dotfiles_path"
    log "既存のディレクトリを再利用します。"
    success "dotfiles のクローンが完了しました。"
    return
  fi

  log "dotfiles リポジトリをクローンしています..."

  # まず SSH でクローンを試みる
  if ghq get git@github.com:$GITHUB_USERNAME/my.dotfiles.git 2>/dev/null; then
    success "SSH でのクローンが完了しました。"
    log "SSH キーが正しく設定されています。"
  else
    warn "SSH 接続に失敗しました。HTTPS でクローンします。"
    log "SSH キーが設定されていないか、アクセス権限がない可能性があります。"

    ghq get https://github.com/$GITHUB_USERNAME/my.dotfiles.git
    success "HTTPS でのクローンが完了しました。"
  fi

  if [ -d "$dotfiles_path" ]; then
    success "dotfiles のクローンが完了しました。"
    log "クローン先：$dotfiles_path"
    log "dotfiles の設定ファイルが利用可能になりました。"
  else
    error "dotfiles のクローンに失敗しました。ネットワーク接続とアクセス権限を確認してください。"
  fi
}

install_brew_packages() {
  step "Homebrew パッケージのインストールを開始します。"

  local dotfiles_path
  dotfiles_path=$(normalized_dotfiles_path)
  local brewfile_path="$dotfiles_path/brew/Brewfile"

  if [ -f "$brewfile_path" ]; then
    log "Brewfile からパッケージをインストールしています..."

    # curl を先行インストール（brew bundle 実行に必要）
    if ! brew list curl &>/dev/null; then
      brew install curl
    fi

    # Homebrew の curl を使用
    export HOMEBREW_CURL_PATH="/home/linuxbrew/.linuxbrew/bin/curl"
    brew bundle --file="$brewfile_path"

    # インストール済みパッケージと Brewfile を比較して管理対象外パッケージを検出
    local installed expected unmanaged
    installed=$(brew leaves 2>/dev/null | sort)
    expected=$(grep '^brew "' "$brewfile_path" 2>/dev/null | sed 's/brew "\([^"]*\)".*/\1/' | sort)
    unmanaged=$(comm -23 <(echo "$installed") <(echo "$expected"))

    if [ -n "$unmanaged" ]; then
      warn "以下の Homebrew パッケージは Brewfile に含まれていません："
      echo "$unmanaged"
      read -r -p "これらのパッケージを削除しますか？（y/N）> " response
      if [[ "$response" =~ ^[Yy]$ ]]; then
        echo "$unmanaged" | xargs brew uninstall --force
        brew autoremove
        log "管理対象外パッケージを削除しました。"
      else
        log "管理対象外パッケージの削除をスキップしました。"
      fi
    else
      log "管理対象外の Homebrew パッケージはありません。"
    fi
  else
    warn "Brewfile が見つかりません：$brewfile_path"
  fi

  success "Homebrew パッケージのインストールが完了しました。"
}

install_fisher_plugins() {
  step "Fisher プラグインのインストールを開始します。"

  local dotfiles_path
  dotfiles_path=$(normalized_dotfiles_path)
  local plugins_file="$dotfiles_path/fish/fish_plugins"

  # Fisher がインストールされていない場合はインストール
  if [ ! -f ~/.config/fish/functions/fisher.fish ]; then
    log "Fisher プラグインマネージャーをインストールしています..."
    fish -c "curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source && fisher install jorgebucaran/fisher"
  else
    log "Fisher は既にインストール済みです。"
  fi

  # fish_plugins からプラグインをインストール
  if [ -f "$plugins_file" ]; then
    log "fish_plugins からプラグインをインストールしています..."
    while IFS= read -r plugin || [ -n "$plugin" ]; do
      [ -z "$plugin" ] && continue
      [[ "$plugin" =~ ^# ]] && continue
      if ! fish -c "fisher list | grep -q '$plugin'" 2>/dev/null; then
        log "インストール中：$plugin"
        fish -c "fisher install $plugin" 2>/dev/null || true
      fi
    done <"$plugins_file"

    # インストール済みプラグインと fish_plugins を比較して管理対象外プラグインを検出
    local installed expected unmanaged
    installed=$(fish -c "fisher list" 2>/dev/null | sort)
    expected=$(grep -v '^#' "$plugins_file" 2>/dev/null | grep -v '^$' | sort)
    unmanaged=$(comm -23 <(echo "$installed") <(echo "$expected"))

    if [ -n "$unmanaged" ]; then
      warn "以下の Fisher プラグインは fish_plugins に含まれていません："
      echo "$unmanaged"
      read -r -p "これらのプラグインを削除しますか？（y/N）> " response
      if [[ "$response" =~ ^[Yy]$ ]]; then
        echo "$unmanaged" | while read -r plugin; do
          [ -n "$plugin" ] && fish -c "fisher remove $plugin" 2>/dev/null || true
        done
        log "管理対象外プラグインを削除しました。"
      else
        log "管理対象外プラグインの削除をスキップしました。"
      fi
    else
      log "管理対象外の Fisher プラグインはありません。"
    fi
  else
    warn "fish_plugins が見つかりません：$plugins_file"
  fi

  # ベースの ghq キーバインド設定を削除
  rm -f ~/.config/fish/conf.d/ghq_key_bindings.fish ~/.config/fish/functions/__ghq_repository_search.fish 2>/dev/null || true

  success "Fisher プラグインのインストールが完了しました。"
}

install_node_tools() {
  step "Node.js ツールのインストールを開始します。"

  # Homebrew の Node.js と nvm.fish の競合を解消
  log "Homebrew と nvm.fish の Node.js 競合を解消しています..."
  brew uninstall node --ignore-dependencies 2>/dev/null || true

  if ! fish -c "functions -q nvm" 2>/dev/null; then
    log "Node.js バージョン管理ツール（nvm.fish）をインストールしています..."
    fish -c "fisher install jorgebucaran/nvm.fish" 2>/dev/null || true
  else
    log "nvm.fish は既にインストール済みです。スキップします。"
  fi

  log "Node.js LTS バージョンをデフォルトとして設定しています..."
  fish -c "nvm install lts" 2>/dev/null || true
  fish -c "set --universal nvm_default_version lts" 2>/dev/null || true
  log "Node.js LTS バージョンをインストールし、デフォルトに設定しました"

  log "pnpm 用に corepack を有効化しています..."
  fish -c "nvm use lts; corepack enable" 2>/dev/null || true

  success "Node.js ツールのインストールが完了しました。"
}

verify() {
  step "設定の検証を開始します。"

  log "Nerd Font アイコンテスト..."
  printf "\ue5fe \uf07b \uf1c0 \uf0c7 \uf013\n"

  log "インストール済みツールを確認しています..."
  echo "Fish：$(fish --version 2>/dev/null || echo '❌')"
  echo "Neovim：$(nvim --version | head -n1 2>/dev/null || echo '❌')"
  echo "ghq：$(ghq --version 2>/dev/null || echo '❌')"
  echo "GitHub CLI：$(gh --version 2>/dev/null | head -n1 || echo '❌')"

  log "設定ファイルを確認しています..."
  echo "Fish 設定：$([ -f ~/.config/fish/config.fish ] && echo '✅' || echo '❌')"
  echo "Git 設定：$([ -f ~/.gitconfig ] && echo '✅' || echo '❌')"
  echo "Neovim 設定：$([ -f ~/.config/nvim/init.lua ] && echo '✅' || echo '❌')"
  echo "SSH 設定：$([ -f ~/.ssh/config ] && echo '✅' || echo '❌')"

  success "設定の検証が完了しました。"
}

manual_tasks() {
  step "手動タスクを開始してください。"

  # 管理対象外の apt パッケージを確認します
  unmanaged_apt_packages

  success "手動タスク："

  success "1. Windows にフォントをインストール"
  echo "   https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip"
  echo "   zip を展開後、.ttf ファイルを右クリックしてインストール"

  success "2. Windows Terminal のフォント設定"
  echo "   Ctrl + , → プロファイル → Ubuntu → 外観"
  echo "   フォントフェイスを 'JetBrains Mono' に変更して再起動"

  success "3. SSH キーのセットアップ（任意）"
  if [ -n "${GITHUB_SSH_KEY:-}" ]; then
    echo "   秘密鍵を ~/.ssh/github/$GITHUB_SSH_KEY に配置"
    echo "   chmod 600 ~/.ssh/github/$GITHUB_SSH_KEY"
    echo "   ssh -T git@github.com でテスト"
  else
    echo "   スキップ"
  fi

  success "4. PowerShell 設定（任意）"
  echo "   power-shell/Microsoft.PowerShell_profile.ps1 を Windows の \$PROFILE にコピー"
}

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --sync)
      SYNC_ONLY=true
      shift
      ;;
    -y | --yes)
      SKIP_CONFIRM=true
      shift
      ;;
    -h | --help)
      help
      exit 0
      ;;
    *)
      warn "不明なオプション：$1"
      help
      exit 1
      ;;
    esac
  done

  if [ "$SYNC_ONLY" == "true" ]; then
    # --sync モードの場合は設定ファイルの同期のみ実行
    SYNC_STEPS=(
      prepare_wsl2
      prepare_user
      configure_dotfiles
      configure_git
      verify
    )
    TOTAL_STEPS=${#SYNC_STEPS[@]}
    success "🔄 setup.sh --sync"

    for step in "${SYNC_STEPS[@]}"; do
      $step
    done

    success "✨ 同期が完了しました"
  else
    # フルセットアップを実行
    TOTAL_STEPS=$(grep -c "step \"" "$0")
    success "🚀 setup.sh"

    prepare_wsl2
    prepare_user

    install_apt_tools
    install_brew_packages
    install_fonts
    install_fisher_plugins
    install_node_tools
    install_dotfiles

    configure_default_shell
    configure_ghq
    configure_dotfiles
    configure_git

    verify
    manual_tasks

    success "✨ 自動セットアップが完了しました"
  fi
}

main "$@"
