function repeat_help
    echo "🕒 repeat - コマンド繰り返しツール

[使用方法]
repeat [回数:REQUIRED] [オプション] [コマンド:REQUIRED]

[説明]
指定されたコマンドを指定回数実行します。

[オプション]
-h, --help     このヘルプを表示

[例]
repeat 3 echo 'Hello'
repeat 5 ls -l"
end

function repeat -d 指定されたコマンドを指定回数実行
    argparse h/help -- $argv
    or return

    if set -q _flag_help
        repeat_help
        return 0
    end

    if test (count $argv) -lt 2
        repeat_help
        return 1
    end

    set -l repeat_count $argv[1]

    if not string match -qr '^[0-9]+$' -- $repeat_count
        set_color red
        echo "⛔ 回数には正の整数を指定してください"
        set_color normal
        return 1
    end

    set -l command $argv[2..-1]

    for i in (seq $repeat_count)
        echo "$i/$repeat_count"
        $command
    end
end
