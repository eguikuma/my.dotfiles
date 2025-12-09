function flatten_help
    echo "📦 flatten - ディレクトリ構造をフラット化してコピー

[使用方法]
flatten [入力ディレクトリ:REQUIRED] [オプション]

[説明]
ディレクトリ配下のファイルを、階層構造を反映したフラットなファイル名へ変換してコピーします。
※ デフォルトで隠しファイルおよび隠しディレクトリは除外されます。
※ デフォルトで.gitignoreに記載されたパターンは除外されます。

[オプション]
-h, --help            このヘルプを表示
-a, --all             .gitignoreを無視して全ファイルを対象
-i, --include PAT     含めるパターン（カンマ区切りで複数指定可能）
                      ファイル名またはパスの一部にマッチ
                      例：-i \"*.ts\"  または  -i \"*.ts,*.tsx\"
-e, --exclude PAT     除外するパターン（カンマ区切りで複数指定可能）
                      ファイル名またはパスの一部にマッチ
                      例：-e \"*.test.ts,*.spec.ts\" / -e node_modules
-o, --output DIR      出力先ディレクトリ（デフォルト：flatten）
-c, --copy            ハードリンクの代わりに実コピーを使用
-z, --zip             ZIP形式で出力
-v, --verbose         詳細な実行情報を表示

[例]
flatten src
flatten src -i \"*.ts\"
flatten src -i \"*.ts,*.tsx\" -e \"*.test.ts,*.spec.ts\"
flatten src -e node_modules
flatten src -o my-output
flatten src -z
flatten src -a
flatten src -i \"*.ts\" -e \"*.test.ts\" -o output -v"
end

function flatten -d ディレクトリ構造をフラット化してコピー
    argparse h/help a/all c/copy 'i/include=' 'e/exclude=' 'o/output=' z/zip v/verbose -- $argv
    or return

    if set -q _flag_help
        flatten_help
        return 0
    end

    # fd：高速ファイル検索に使用（.gitignore 対応）
    if not command -v fd >/dev/null
        set_color red
        echo "⛔ fd コマンドが見つかりません（brew install fd）" >&2
        set_color normal
        return 1
    end

    # awk：テキスト処理に使用（フィルタリング、ツリー生成）
    if not command -v awk >/dev/null
        set_color red
        echo "⛔ awk コマンドが見つかりません" >&2
        set_color normal
        return 1
    end

    # realpath：絶対パス変換に使用
    if not command -v realpath >/dev/null
        set_color red
        echo "⛔ realpath コマンドが見つかりません（brew install coreutils）" >&2
        set_color normal
        return 1
    end

    # xargs：バルク処理に使用
    if not command -v xargs >/dev/null
        set_color red
        echo "⛔ xargs コマンドが見つかりません" >&2
        set_color normal
        return 1
    end

    # 入力ディレクトリのバリデーション
    if test (count $argv) -eq 0
        flatten_help
        return 1
    end

    set -l input_dir $argv[1]

    if not test -d $input_dir
        set_color red
        echo "⛔ $input_dir は存在しません" >&2
        set_color normal
        return 1
    end

    # 入力ディレクトリのパスを正規化（./ や 末尾の / を除去）
    set input_dir (string replace -r '^\./' '' $input_dir)
    set input_dir (string replace -r '/$' '' $input_dir)
    if test -z "$input_dir"
        set input_dir "."
    end

    # 入力ディレクトリの絶対パスを保存（cdするとfishでは親シェルも移動するためrealpathを使用）
    set -l abs_input_dir (realpath $input_dir)

    # オプションの設定
    set -l include_patterns
    if set -q _flag_include
        set include_patterns (string split "," $_flag_include)
    end

    set -l exclude_patterns
    if set -q _flag_exclude
        set exclude_patterns (string split "," $_flag_exclude)
    end

    set -l output_dir flatten
    if set -q _flag_output
        set output_dir $_flag_output
    end

    set -l zip_mode false
    if set -q _flag_zip
        set zip_mode true
        # zipコマンドの存在確認
        if not command -v zip >/dev/null
            set_color red
            echo "⛔ zipコマンドが見つかりません" >&2
            set_color normal
            return 1
        end
    end

    set -l verbose false
    if set -q _flag_verbose
        set verbose true
    end

    set -l ignore_gitignore false
    if set -q _flag_all
        set ignore_gitignore true
    end

    # 出力ディレクトリの準備
    if test -d $output_dir
        if test "$verbose" = true
            set_color cyan
            echo "⚙️️ 出力ディレクトリを削除しています"
            set_color normal
        end
        rm -rf $output_dir
    end
    command mkdir -p $output_dir

    if test "$verbose" = true
        echo "⚙️️ $input_dir を $output_dir にコピーします"
        echo "⚙️️ $include_patterns を含めます"
        echo "⚙️️ $exclude_patterns を除外します"
        if test "$ignore_gitignore" = true
            echo "⚙️️ .gitignoreを無視します"
        else
            echo "⚙️️ .gitignoreを尊重します"
        end
        if test "$zip_mode" = true
            echo "⚙️️ ZIP出力は有効です"
        else
            echo "⚙️️ ZIP出力は無効です"
        end
    end

    # ファイル検索（fd または git ls-files）
    set_color cyan
    echo "⚙️️ ファイルを検索しています"
    set_color normal

    set -l all_files
    set -l search_method ""

    set -l is_git_repo false
    set -l git_root ""
    if git -C $input_dir rev-parse --git-dir >/dev/null 2>&1
        set is_git_repo true
        set git_root (git -C $input_dir rev-parse --show-toplevel 2>/dev/null)
    end

    if test "$ignore_gitignore" = true
        # --all オプション：.gitignore を無視（隠しファイルは引き続き除外）
        if command -v fd >/dev/null 2>&1
            set search_method "fd --no-ignore"
            # fdの結果を絶対パスに一括変換（xargsでバルク処理）
            set all_files (command fd --type f --no-ignore . $input_dir 2>/dev/null | \
                xargs -d '\n' realpath 2>/dev/null | sort -u)
        else
            set search_method find
            # findの結果を絶対パスに一括変換（xargsでバルク処理）
            set all_files (command find $input_dir -type f -not -path '*/.*' 2>/dev/null | \
                xargs -d '\n' realpath 2>/dev/null | sort -u)
        end
    else
        # デフォルト：.gitignore を尊重して検索
        if test "$is_git_repo" = true
            set search_method "git ls-files"

            # git_rootからの相対パスを計算
            set -l relative_input (string replace "$git_root/" "" $abs_input_dir)
            if test "$relative_input" = "$abs_input_dir"
                set relative_input ""
            end

            # git ls-files実行
            set -l git_files
            if test -z "$relative_input"
                set git_files (git -C $git_root ls-files --cached --others --exclude-standard 2>/dev/null)
            else
                set git_files (git -C $git_root ls-files --cached --others --exclude-standard "$relative_input/" 2>/dev/null)
            end

            # ファイルをawkで一括フィルタリング（隠しファイル除外 + 存在確認）
            # ※ xargs -I{} は O(n) プロセス起動で遅いため、バッチ処理を使用
            set all_files (printf "%s\n" $git_files | \
                awk -v root="$git_root" '
                    # 空行スキップ
                    /^$/ { next }
                    # 隠しファイル/ディレクトリをスキップ（先頭が.または/の直後が.）
                    /^\./ { next }
                    /\/\./ { next }
                    { print root "/" $0 }
                ' | xargs -d '\n' sh -c 'for f; do test -f "$f" && echo "$f"; done' _ | sort -u)
        else if command -v fd >/dev/null 2>&1
            set search_method fd
            # fdの結果を絶対パスに一括変換
            set all_files (command fd --type f . $input_dir 2>/dev/null | \
                xargs -d '\n' realpath 2>/dev/null | sort -u)
        else
            set search_method "find (フォールバック)"
            set_color yellow >&2
            echo "⚠️ .gitignoreの尊重にはfdまたはGitリポジトリが必要です" >&2
            set_color normal >&2
            # findの結果を絶対パスに一括変換
            set all_files (command find $input_dir -type f -not -path '*/.*' 2>/dev/null | \
                xargs -d '\n' realpath 2>/dev/null | sort -u)
        end
    end

    if test "$verbose" = true
        echo "⚙️️ $search_method を使用しました"
    end

    # -i で指定された具体的なファイル名を直接追加（.gitignore関係なく）
    set -l current_dir (pwd)
    for pattern in $include_patterns
        # ワイルドカードを含まない場合（具体的なファイル名）
        if not string match -q '*\**' $pattern; and not string match -q '*\?*' $pattern
            set -l target_file
            if test "$input_dir" = "."
                set target_file "$current_dir/$pattern"
            else
                set target_file "$abs_input_dir/$pattern"
            end
            # ファイルが存在し、まだリストに含まれていなければ追加
            if test -f "$target_file"
                if not contains $target_file $all_files
                    set -a all_files $target_file
                    if test "$verbose" = true
                        echo "⚙️️ $target_file を追加しました"
                    end
                end
            end
        end
    end

    # 空エントリを除外
    set all_files (string match -v '' $all_files)

    if test (count $all_files) -eq 0
        set_color red
        echo "⛔ 指定されたディレクトリ内にファイルは見つかりません" >&2
        set_color normal
        return 1
    end

    # フィルタリング（include/exclude パターンの適用）
    set_color cyan
    echo "⚙️️ フィルタリングしています"
    set_color normal

    # awk用にパターンを準備（カンマ区切り）
    set -l include_str (string join "," $include_patterns)
    set -l exclude_str (string join "," $exclude_patterns)

    # awkによる一括フィルタリング（include/excludeはgawk予約語のためinc_pats/exc_patsを使用）
    set -l target_files (printf "%s\n" $all_files | awk -v abs_input="$abs_input_dir" \
        -v cur_dir="$current_dir" -v inc_pats="$include_str" -v exc_pats="$exclude_str" '
    # glob_match: シンプルなワイルドカードマッチ（*.ts, *.test.ts など）
    function glob_match(str, pat,    prefix, suffix, star_pos) {
        if (pat == "") return 1
        if (pat == "*") return 1

        star_pos = index(pat, "*")
        if (star_pos == 0) {
            # ワイルドカードなし: 完全一致
            return (str == pat)
        } else if (star_pos == 1) {
            # 先頭が * : 末尾マッチ（*.ts → .tsで終わる）
            suffix = substr(pat, 2)
            if (suffix == "") return 1
            # 2つ目の*があるか確認
            if (index(suffix, "*") > 0) {
                # *.test.* のような複雑なパターン → 含まれていればOK
                gsub(/\*/, "", suffix)
                return (index(str, suffix) > 0)
            }
            return (substr(str, length(str) - length(suffix) + 1) == suffix)
        } else {
            # 先頭以外に * : プレフィックス + サフィックスで分割
            prefix = substr(pat, 1, star_pos - 1)
            suffix = substr(pat, star_pos + 1)
            if (index(str, prefix) != 1) return 0
            if (suffix == "") return 1
            return (substr(str, length(str) - length(suffix) + 1) == suffix)
        }
    }
    BEGIN {
        n_inc = split(inc_pats, inc_arr, ",")
        n_exc = split(exc_pats, exc_arr, ",")
    }
    {
        if ($0 == "") next

        path = $0

        # basename抽出（awk内で計算）
        n = split(path, parts, "/")
        basename = parts[n]

        # 相対パス計算
        if (index(path, abs_input "/") == 1) {
            rel = substr(path, length(abs_input) + 2)
        } else if (index(path, cur_dir "/") == 1) {
            rel = substr(path, length(cur_dir) + 2)
        } else {
            rel = path
        }

        # includeパターンチェック
        if (n_inc > 0 && inc_arr[1] != "") {
            matched = 0
            for (i = 1; i <= n_inc; i++) {
                pat = inc_arr[i]
                if (pat == "") continue
                # ファイル名でマッチ
                if (glob_match(basename, pat)) {
                    matched = 1
                    break
                }
                # パターンが * で始まらない場合のみパス全体でマッチ
                if (substr(pat, 1, 1) != "*") {
                    if (index(rel, pat) > 0) {
                        matched = 1
                        break
                    }
                }
            }
            if (!matched) next
        }

        # excludeパターンチェック
        for (i = 1; i <= n_exc; i++) {
            pat = exc_arr[i]
            if (pat == "") continue
            if (glob_match(basename, pat)) next
            if (substr(pat, 1, 1) != "*") {
                if (index(rel, pat) > 0) next
            }
        }

        print path
    }')

    if test (count $target_files) -eq 0
        set_color red
        echo "⛔ 指定されたパターンに一致するファイルは見つかりません" >&2
        set_color normal
        return 1
    end

    if test "$verbose" = true
        set count (count $target_files)
        echo "⚙️️ $count ファイルを検出しました"
    end

    # フラット化（ハードリンク作成、--copy で実コピー）
    set_color cyan
    echo "⚙️️ フラット化しています"
    set_color normal

    # awkで src\ndest 形式のペアを生成
    set -l copy_pairs_file (mktemp)
    set -l skip_count 0

    printf "%s\n" $target_files | awk -v abs_input="$abs_input_dir" \
        -v cur_dir="$current_dir" -v in_dir="$input_dir" -v out_dir="$output_dir" '
    {
        path = $0
        # 相対パス計算
        if (index(path, abs_input "/") == 1) {
            rel = substr(path, length(abs_input) + 2)
        } else if (index(path, cur_dir "/") == 1) {
            rel = substr(path, length(cur_dir) + 2)
        } else {
            rel = path
        }

        # フラット名生成（in_dirの/も.に変換）
        flat = rel
        gsub(/\//, ".", flat)
        if (in_dir == ".") {
            flat_name = flat
        } else {
            in_dir_flat = in_dir
            gsub(/\//, ".", in_dir_flat)
            flat_name = in_dir_flat "." flat
        }
        sub(/^\./, "", flat_name)

        # 衝突チェック（awk内で完結）
        dest = out_dir "/" flat_name
        if (!(dest in seen)) {
            seen[dest] = 1
            # src\ndest 形式で出力（xargs -n2 用）
            print path
            print dest
        }
    }' >$copy_pairs_file

    # --copy オプションが指定されていない場合、ハードリンクを試行
    set -l use_hardlink false
    if not set -q _flag_copy
        set -l test_link (mktemp -u "$output_dir/.hardlink_test_XXXXXX")
        if test (count $target_files) -gt 0
            if ln "$target_files[1]" "$test_link" 2>/dev/null
                rm -f "$test_link"
                set use_hardlink true
            end
        end
    end

    # bashスクリプトで並列実行（/dev/shm 使用）
    set -l copy_script
    if test -d /dev/shm
        set copy_script /dev/shm/flatten_script_$fish_pid
    else
        set copy_script (mktemp)
    end

    set -l batch_size 1000
    if test "$use_hardlink" = true
        awk -v batch="$batch_size" '
            NR%2==1 {src=$0}
            NR%2==0 {
                print "ln \"" src "\" \"" $0 "\" &"
                if ((NR/2) % batch == 0) print "wait"
            }
            END { print "wait" }
        ' $copy_pairs_file >$copy_script
    else
        awk -v batch="$batch_size" '
            NR%2==1 {src=$0}
            NR%2==0 {
                print "cp \"" src "\" \"" $0 "\" &"
                if ((NR/2) % batch == 0) print "wait"
            }
            END { print "wait" }
        ' $copy_pairs_file >$copy_script
    end
    bash $copy_script 2>/dev/null
    rm -f $copy_script

    # 成功数をカウント（出力ディレクトリ内のファイル数、tree.txt除く）
    set -l success_count (command find $output_dir -type f -not -name 'tree.txt' 2>/dev/null | wc -l | string trim)

    # 一時ファイル削除
    rm -f $copy_pairs_file

    # verbose モードの場合はコピー内容を表示
    if test "$verbose" = true
        for file in $target_files
            set -l rel (string replace "$abs_input_dir/" "" $file)
            if test "$rel" = "$file"
                set rel (string replace "$current_dir/" "" $file)
            end
            set -l flat (string replace -a "/" "." $rel)
            if test "$input_dir" != "."
                set -l in_flat (string replace -a "/" "." $input_dir)
                set flat "$in_flat.$flat"
            end
            set flat (string replace -r '^\.' '' $flat)
            echo "⚙️️ $rel → $flat"
        end
    end

    # ツリー構造の生成（tree.txt）
    set_color cyan
    echo "⚙️️ ツリー構造を生成しています"
    set_color normal
    __flatten_generate_tree $input_dir $target_files $output_dir $abs_input_dir

    if test "$zip_mode" = true
        set_color cyan
        echo "⚙️️ ZIP化しています"
        set_color normal

        set -l zip_name "$output_dir.zip"
        set -l current_dir (pwd)
        cd (dirname $output_dir)

        zip -rq $zip_name (basename $output_dir)
        set -l zip_status $status

        cd $current_dir

        if test $zip_status -eq 0
            set_color green
            echo "✅ ZIP化に成功しました"
            set_color normal
        else
            set_color red
            echo "⛔ ZIP化に失敗しました" >&2
            set_color normal
        end
    end

    set_color green
    echo "✅ ディレクトリ構造のフラット化に成功しました"
    set_color normal

    echo "ℹ️ $success_count ファイルを出力しました"
    echo "ℹ️ $skip_count ファイルをスキップしました"
    echo "ℹ️ $output_dir に出力されました"

    return 0
end

function __flatten_generate_tree -d フラット化対象のツリー構造を生成
    set -l input_dir $argv[1]
    set -l target_files $argv[2..-3]
    set -l output_dir $argv[-2]
    set -l abs_input_dir $argv[-1]

    set -l tree_file "$output_dir/tree.txt"

    # awkによる一括処理
    # パス分解・エントリ収集 → sort -u → ツリー生成
    printf "%s\n" $target_files | awk -v abs_input_dir="$abs_input_dir" '
    {
        # 相対パスを抽出
        rel_path = substr($0, length(abs_input_dir) + 2)

        # ディレクトリ構造を分解して収集
        n = split(rel_path, parts, "/")
        path = ""
        for (i = 1; i < n; i++) {
            path = path parts[i] "/"
            if (!(path in seen)) {
                seen[path] = 1
                print path
            }
        }
        # ファイル自体を追加
        if (!(rel_path in seen)) {
            seen[rel_path] = 1
            print rel_path
        }
    }
    ' | sort -u | awk -v input_dir="$input_dir" '
    BEGIN {
        n = 0
    }
    {
        entries[++n] = $0
        entry = $0

        # ディレクトリかどうか
        is_dir[n] = (substr(entry, length(entry)) == "/")

        # クリーンパス（末尾/除去）
        if (is_dir[n]) {
            clean[n] = substr(entry, 1, length(entry) - 1)
        } else {
            clean[n] = entry
        }

        # 深さと名前を計算
        num_parts = split(clean[n], parts, "/")
        depth[n] = num_parts
        name[n] = parts[num_parts]

        # 親ディレクトリを計算
        parent[n] = ""
        for (i = 1; i < num_parts; i++) {
            if (i == 1) {
                parent[n] = parts[i]
            } else {
                parent[n] = parent[n] "/" parts[i]
            }
        }
    }
    END {
        # 逆順走査でis_last判定（連想配列でO(1)）
        for (i = n; i >= 1; i--) {
            p = parent[i]
            if (p in seen_parents) {
                is_last[i] = 0
            } else {
                is_last[i] = 1
                seen_parents[p] = 1
            }
        }

        # ツリー出力
        print input_dir "/"

        for (i = 1; i <= n; i++) {
            # last_at_depthを更新
            last_at_depth[depth[i]] = is_last[i]

            # インデント計算
            indent = ""
            for (d = 1; d < depth[i]; d++) {
                if (last_at_depth[d]) {
                    indent = indent "    "
                } else {
                    indent = indent "│   "
                }
            }

            # プレフィックス
            if (is_last[i]) {
                prefix = "└──"
            } else {
                prefix = "├──"
            }

            # 出力
            if (is_dir[i]) {
                if (entries[i] != last_printed_dir) {
                    print indent prefix " " name[i]
                    last_printed_dir = entries[i]
                }
            } else {
                # フラット名生成
                flat = clean[i]
                gsub(/\//, ".", flat)
                if (input_dir == ".") {
                    flat_name = flat
                } else {
                    flat_name = input_dir "." flat
                }
                sub(/^\./, "", flat_name)

                print indent prefix " " name[i] " → " flat_name
            }
        }
    }
    ' >"$tree_file"
end
