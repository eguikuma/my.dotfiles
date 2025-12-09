function fish_prompt
    if not set -q VIRTUAL_ENV_DISABLE_PROMPT
        set -g VIRTUAL_ENV_DISABLE_PROMPT true
    end

    set -g __fish_git_prompt_showdirtystate yes
    set -g __fish_git_prompt_showuntrackedfiles yes
    set -g __fish_git_prompt_showstashstate yes
    set -g __fish_git_prompt_showupstream informative

    set -g __fish_git_prompt_char_dirtystate '*'
    set -g __fish_git_prompt_char_stagedstate '+'
    set -g __fish_git_prompt_char_untrackedfiles '%'
    set -g __fish_git_prompt_char_stashstate '$'
    set -g __fish_git_prompt_char_upstream_ahead '↑'
    set -g __fish_git_prompt_char_upstream_behind '↓'
    set -g __fish_git_prompt_char_upstream_diverged '↑↓'
    set -g __fish_git_prompt_char_upstream_equal ''

    set_color 13a10e
    printf '@WSL(%s) ' (command grep PRETTY_NAME /etc/os-release | sed -E "s/.*\"([^\"]+)\".*/\1/")

    set fish_prompt_pwd_dir_length 3
    set_color normal
    printf '%s ' (prompt_pwd)

    set -l git_info (fish_git_prompt | string replace -ra '[\(\) ]' '')

    if test -n "$git_info"
        set -l branch_only (echo $git_info | string replace -ra '[*+%$↑↓0-9]' '')
        if test "$git_info" = "$branch_only"
            set_color 13a10e -o -u
        else
            set_color ffff00 -o -u
        end
        printf '%s' $git_info
    end

    if test -n "$VIRTUAL_ENV"
        printf " (%s)" (set_color blue)(basename $VIRTUAL_ENV)(set_color normal)
    end

    echo

    set_color normal
    printf '$ '
end
