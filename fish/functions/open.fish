function open_help
    echo "🔗 open - ファイル・ディレクトリ・URL オープンツール

[使用方法]
open [対象 | オプション]

[説明]
指定されたファイル、ディレクトリ、またはURLをWindows側のデフォルトアプリケーションで開きます。
複数の項目を同時に開くことも可能です。

[オプション]
-h, --help        このヘルプを表示
-d, --directory   ディレクトリとして強制的に開く
-v, --verbose     詳細な実行情報を表示

[例]
open file.txt
open image.jpg document.pdf
open .
open ~/Documents
open https://github.com
open -d file.txt
open -v file.html"
end

function open -d "ファイル・ディレクトリ・URLをWindows側で開く"
    argparse h/help d/directory v/verbose -- $argv
    or return

    if set -q _flag_help
        open_help
        return 0
    end

    if test (count $argv) -eq 0
        set argv "."
    end

    set -l verbose false
    if set -q _flag_verbose
        set verbose true
    end

    set -l force_directory false
    if set -q _flag_directory
        set force_directory true
    end

    # コマンドの利用可否を確認
    set -l use_explorer false
    set -l use_cmd false

    if command -v explorer.exe >/dev/null
        set use_explorer true
    else
        set use_cmd true
    end

    if test "$verbose" = true
        if test "$use_explorer" = true
            echo "⚙️ explorer.exe を使用します"
        else
            echo "⚙️ cmd.exe を使用します（フォールバック）"
        end
    end

    for target in $argv
        set -l is_url false
        if string match -qr '^https?://' -- $target
            set is_url true
        end

        # -d オプション：ファイルが指定された場合は親ディレクトリを開く
        if test "$force_directory" = true -a "$is_url" = false
            if test -f $target
                set target (dirname $target)
            end
        end

        if test "$is_url" = false
            if not test -e $target
                set_color yellow
                echo "⚠️ $target は存在しないためスキップします"
                set_color normal
                continue
            end
        end

        if test "$verbose" = true
            if test "$is_url" = true
                echo "⚙️ $target というURLを開いています"
            else if test -d $target
                echo "⚙️ $target というディレクトリを開いています"
            else
                echo "⚙️ $target というファイルを開いています"
            end
        end

        set -l exit_code 0
        set -l used_command ""

        if test "$use_explorer" = true
            # URL は cmd.exe start 経由で開く（explorer.exe は URL を直接処理できない）
            if test "$is_url" = true
                set used_command "cmd.exe start"
                if test "$verbose" = true
                    cmd.exe /c start "$target"
                    set exit_code $status
                else
                    cmd.exe /c start "$target" >/dev/null 2>&1
                    set exit_code $status
                end
            else
                # ファイル・ディレクトリは Windows パスに変換して explorer.exe で開く
                set used_command "explorer.exe"
                set -l windows_path (wslpath -w "$target" 2>/dev/null)
                if test $status -eq 0
                    if test "$verbose" = true
                        explorer.exe "$windows_path"
                        set exit_code $status
                    else
                        explorer.exe "$windows_path" >/dev/null 2>&1
                        set exit_code $status
                    end
                end
            end
        else if test "$use_cmd" = true
            # cmd.exe をフォールバックとして使用
            set used_command "cmd.exe"
            if test "$is_url" = false
                set -l windows_path (wslpath -w "$target" 2>/dev/null)
                if test $status -eq 0
                    set target "$windows_path"
                end
            end

            if test "$verbose" = true
                cmd.exe /c start "$target"
                set exit_code $status
            else
                cmd.exe /c start "$target" >/dev/null 2>&1
                set exit_code $status
            end
        end

        if test "$verbose" = true
            echo "⚙️ $used_command を使用しました"
            echo "⚙️ 終了コードは $exit_code でした"
        end
    end

    return 0
end
