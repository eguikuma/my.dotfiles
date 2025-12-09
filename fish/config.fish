if status is-interactive
end

set -x PATH $PATH:'/mnt/c/Users/{{WINDOWS_USERNAME}}/AppData/Local/Programs/Microsoft VS Code/bin'
set -x PATH $PATH:'/opt/nvim'

set -gx FZF_DEFAULT_OPTS "
  --prompt='🔎 '
  --inline-info
  --height=40%
  --reverse
  --header=''
  --margin=0,0,0,0
  --padding=1,2
  --pointer=' >'
  --gutter=' '
  --marker='✓'
  --no-hscroll
  --info=inline
  --color=dark
  --color=fg:#c0caf5,bg:-1,hl:#f7768e
  --color=fg+:#ffffff,bg+:#283457,hl+:#f7768e
  --color=prompt:#7aa2f7,pointer:#ffffff,marker:#9ece6a
  --color=info:#7dcfff,spinner:#bb9af7,header:#7aa2f7
  --color=gutter:-1,border:-1
  --bind='ctrl-p:toggle-preview'
  --ellipsis=...
  --tabstop=4
  --preview-window=right:70%:wrap
  --color=gutter:-1,border:#1A1E22
"
set -gx EDITOR nvim
set -gx VISUAL nvim
set -gx BROWSER explorer.exe

set GHQ_SELECTOR fzf
set fish_greeting

alias .. 'cd ..'
alias ... 'cd ../..'
alias cat bat
alias ls 'eza -lha'
alias find fd
alias grep 'rg --color=always --line-number --heading --pretty'
alias diff 'delta -s'
alias mkdir 'mkdir -p'
alias vim nvim
alias vi nvim
