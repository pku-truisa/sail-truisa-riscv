#!/bin/sh
# ─────────────────────────────────────────────────────────────────────────────
# test/m2/run.sh —— M2 回归基线：一条命令跑完 CADD 三用例（＋容器 L1 自证）
#
# 判据（"必须是什么"）**不在本文件里**，在架构仓：
#   docs/test/m2-baseline.md §三（期望签名）／§四（判据 1–6）
#   docs/test/README.md      §二（L1 容器／L2 指令／L3 语义）
# 本文件只管"怎么跑出来"（docs/test/README.md §一 的分工：判据归架构组，脚本归测试组）。
#
# ⛔ 本脚本不定义期望值：期望值只从 test/m2/expect.csv 读。改期望值＝改判据，
#    只能由架构组改（m2-baseline.md §六）。⛔ 不许为了"变绿"动 expect.csv。
# ⛔ 本脚本不改模型、不改 mkelf.py 的地址布局（m2-baseline.md §一 的表是判据）。
#
# 用法：
#   ./test/m2/run.sh                          # 产物落 build/m2-run/
#   ./test/m2/run.sh --csv <路径>              # 另写一份 CSV（归档进 docs/test/runs/）
#   ./test/m2/run.sh --out <目录>              # 换产物目录
#   SIM=<模拟器路径> ./test/m2/run.sh          # 换模型（默认 build/c_emulator/sail_riscv_sim）
#
# 依赖：① `build/c_emulator/sail_riscv_sim`（M1 产物，由 ./build_emulators.sh 生成）
#       ② `python3`（mkelf.py 的既有依赖，不是本脚本新增）
#       ③ `timeout`（coreutils；只为把"程序没退出"变成失败而不是挂死 —— L1 陷阱 6）
#   ⛔ 不需要编译器／汇编器／链接器／任何新依赖（D-169 §三）。
#
# 退出码：0 全过 ／ 1 有用例失败 ／ 2 环境或前置条件不满足（含"模拟器不存在"）
# ─────────────────────────────────────────────────────────────────────────────

set -u

die() { printf 'ERROR: %s\n' "$*" >&2; exit 2; }

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || die "拿不到脚本目录"
REPO=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd) || die "拿不到仓库根"
EXPECT_FILE="$SCRIPT_DIR/expect.csv"

SIM=${SIM:-"$REPO/build/c_emulator/sail_riscv_sim"}
OUT=${OUT:-"$REPO/build/m2-run"}
CSV=
TIMEOUT_SECS=${M2_TIMEOUT:-60}

while [ $# -gt 0 ]; do
    case "$1" in
        --csv) [ $# -ge 2 ] || die "--csv 需要一个路径"; CSV=$2; shift 2 ;;
        --out) [ $# -ge 2 ] || die "--out 需要一个目录"; OUT=$2; shift 2 ;;
        -h|--help) sed -n '2,28p' "$0"; exit 0 ;;
        *) die "不认识的参数：$1（见 --help）" ;;
    esac
done

# ---------------------------------------------------------------- 前置条件
[ -x "$SIM" ] || die "找不到可执行的模拟器：$SIM（先跑 ./build_emulators.sh，或用 SIM= 指定）"
command -v python3 >/dev/null 2>&1 || die "需要 python3（mkelf.py 的既有依赖）"
command -v timeout >/dev/null 2>&1 || die "需要 coreutils 的 timeout：没有它，L1 陷阱 6（程序不退出）会把回归挂死"
[ -f "$EXPECT_FILE" ] || die "缺少期望值文件：$EXPECT_FILE"

# model@sha 是记录的三问之一（D-106：hash 不带出处就算错）。
# 从 tar/git-archive 展开的构建树没有 .git，此时必须用 MODEL_SHA=<sha> 显式给，
# ⛔ 不许让它悄悄变成 "unknown" 之后还拿去当记录。
MODEL_SHA=${MODEL_SHA:-}
if [ -z "$MODEL_SHA" ]; then
    if git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
        MODEL_SHA=$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo unknown)
    else
        MODEL_SHA=unknown
    fi
fi
SIM_SIZE=$(wc -c < "$SIM" | tr -d ' ')

# arch@sha：`D-183` §五 建议记录同时写判据版本 —— 判据变了而模型没变，同样要重跑。
# 模型仓看不到架构仓，所以由调用方用 ARCH_SHA=<sha> 传；⛔ 不猜、不跨仓去找。
ARCH_SHA=${ARCH_SHA:-unknown}

mkdir -p "$OUT/lib" || die "建不了产物目录：$OUT"

# 运行起止时间：⛔ 这不是装饰 —— `D-182` §六.1 指出，"两份 CSV 的 sha256 相同"能证
# 零行为变化的**前提是 meta.txt 是这次真跑出来的**。若 meta.txt 也是复制来的，那套证据就空转。
# ⇒ 记到秒的起止时间 ＋ 实际耗时，复制不出来（复制两份会连时间一起复制，但与文件 mtime 不符）。
STARTED_AT=$(date '+%Y-%m-%d %H:%M:%S.%N %z')
START_EPOCH=$(date +%s.%N)

# 期望值文件归一化：去 BOM（部分编辑器会写 EF BB BF，会把首行注释读成用例名）、去 CR。
# ⛔ 只做这两件事，不改任何期望值本身。
EXPECT_CLEAN="$OUT/.expect.txt"
tr -d '\357\273\277' < "$EXPECT_FILE" | tr -d '\r' > "$EXPECT_CLEAN" \
    || die "读不了期望值文件：$EXPECT_FILE"

# ---------------------------------------------------------------- 造 ELF
# mkelf.py 是既有实现（D-169）：地址布局属判据（m2-baseline.md §一），本脚本只调用不改。
python3 "$SCRIPT_DIR/mkelf.py" "$OUT/lib" > "$OUT/mkelf.log" 2>&1 \
    || die "mkelf.py 失败，见 $OUT/mkelf.log"

# 归一化：去掉 0x、分隔符、空白，转小写 —— 两边用同一把尺，避免"0x 有没有写"这种假失败
norm() { printf '%s' "$1" | tr -d ' \t\r\n' | tr -d '/' | tr 'A-F' 'a-f' | sed 's/0x//g'; }

nfields() { printf '%s' "$1" | awk -F/ '{print NF}'; }

# is_aligned <16 位小写 hex> -> bit63==1 即 Aligned 模式
#   ⚠️ 守门取子集必须按**实测形态**（bit63），⛔ 不能按 `phase` 列 —— 阶段 B 那天
#   `phase=A` 的行会被摘掉，按列取子集会让守门**跟着一起消失**（判据原文是
#   "所有 phase=A／Aligned 用例"，Aligned 才是那个不随阶段变的口径）。
is_aligned() {
    case "$(printf '%s' "$1" | cut -c1)" in
        8|9|a|b|c|d|e|f) return 0 ;;
        *)               return 1 ;;
    esac
}

# pac_of <16 位小写 hex> -> `bits 56..48` 的 3 位 hex（纯字符串操作，⛔ 不解析成整数）
#   16 位 hex 里：d0=bit63..60，d1=bit59..56，d2/d3=bit55..48…
#   bits 63..57 = d0 整 4 位 ＋ d1 的高 3 位；bits 56..48 = d1 的最低位 ＋ d2 ＋ d3。
#   ⇒ pac = (d1 的最低位) + d2 + d3  —— 例：0x98C8… ⇒ d1='8'(偶) ⇒ "0" + "c8" = "0c8" = 0xC8。
#   ⚠️ 阶段 A 的 `salt=0` 时它不是 0 而是 0xC8；"全部为 0" 只能是没加签（见下面的守门）。
pac_of() {
    w=$1
    d1=$(printf '%s' "$w" | cut -c2)
    case "$d1" in
        1|3|5|7|9|b|d|f) hi=1 ;;
        *)               hi=0 ;;
    esac
    printf '%s%s' "$hi" "$(printf '%s' "$w" | cut -c3-4)"
}

get_sig() {
    # 取签名区前 N 个 8 字节字，按 `0x…/0x…` 连起来（N＝expect 里 `/` 分隔的字段数）。
    # ⭐ 为什么可以多字：有的用例的判据是"两个位点之间的关系"（U4 的 pac 不变式，
    #    D-176 §四），单字签名称不住。⛔ 这不是新加列，只是同一个 signature 字段承载多个字。
    # --test-signature 从 begin_signature 起、按 -g 8 每行 8 字节
    [ -s "$1" ] || { printf '%s' "-"; return; }
    head -n "$2" "$1" | tr -d ' \t\r' | tr 'A-F' 'a-f' | sed 's/^0x//' | awk '
        { printf "%s0x%s", (NR > 1 ? "/" : ""), $0 }'
}

CSV_TMP="$OUT/.m2.csv.tmp"
printf 'case,rc,trap,signature,expect,pass\n' > "$CSV_TMP" || die "写不了 $CSV_TMP"

# ---------------------------------------------------------------- 期望值文件预检
# ⛔ 不许"静默降级"：一条用例的判据是几个字，必须显式写在 words 列里，
#    且与 expect 里的字段数一致。否则把 u4 的 expect 砍成一个字，判据会悄悄
#    从"两个位点"退化成"一个字"，照样判 PASS（D-176 §六.2 立为通则的那类）。
#
# 四列：case,expect,words,phase
#   phase=A ＝ ⭐ 这一行的**绝对值**只是「阶段 A 快照」（`D-182` §4.2）：关系判据长期有效，
#             绝对值只在阶段 A 成立（`pac` 含 `salt`；阶段 B 换真 `salt` 后必变）。
#             ⇒ **进阶段 B 前必须把这一行摘掉或改成关系判据**，否则会出假红灯。
#             phase='-' ＝ 与 `salt` 无关。
check_expect_file() {
    n=0
    PHASE_A_CASES=
    while IFS=, read -r name expect words phase extra; do
        case "$name" in
            ''|'#'*) continue ;;
            case) continue ;;          # 表头
        esac
        printf '%s' "$name" | grep -qE '^[A-Za-z0-9_.-]+$' \
            || die "expect.csv 用例名不合法：$name"
        [ -n "${words:-}" ] || die "expect.csv 缺 words 列：$name（格式：case,expect,words,phase）"
        [ -z "${extra:-}" ] || die "expect.csv 列多于四列：$name"
        printf '%s' "${words}" | grep -qE '^[0-9]+$' || die "expect.csv 的 words 不是整数：$name,$words"
        case "${phase:-}" in
            A) PHASE_A_CASES="${PHASE_A_CASES}${PHASE_A_CASES:+,}$name" ;;
            -) ;;
            *) die "expect.csv 的 phase 只能是 A 或 -：$name,${phase:-<空>}" ;;
        esac
        if [ "$expect" = "-" ]; then
            [ "$words" = "1" ] || die "expect.csv：expect='-' 时 words 必须是 1：$name"
        else
            [ "$(nfields "$expect")" = "$words" ] \
                || die "expect.csv 自相矛盾：$name 声明 words=$words，但 expect 有 $(nfields "$expect") 个字段（⛔ 不许静默降级）"
        fi
        n=$((n + 1))
    done < "$EXPECT_CLEAN"
    [ "$n" -gt 0 ] || die "expect.csv 里一条用例都没读到（$EXPECT_FILE）"
}

check_expect_file

printf 'model@%s  arch@%s  sim=%s (%s B)  out=%s\n' "$MODEL_SHA" "$ARCH_SHA" "$SIM" "$SIM_SIZE" "$OUT"
[ "$ARCH_SHA" = "unknown" ] && \
    printf '⚠️  没传 ARCH_SHA：记录里判据版本缺失（D-183 §五）⇒ 用 ARCH_SHA=<sha> 重跑\n'
[ "$MODEL_SHA" = "unknown" ] && \
    printf '⚠️  这不是 git 树，模型版本未知（D-106）⇒ 用 MODEL_SHA=<sha> 重跑，⛔ 别把本轮记录当基线\n'
if [ -n "$PHASE_A_CASES" ]; then
    printf '⚠️  phase=A 快照：%s —— 其绝对值只在阶段 A 成立（pac 含 salt）\n' "$PHASE_A_CASES"
    printf '    进阶段 B 前必须摘掉这些绝对值（只留关系判据），否则会出假红灯（D-182 §4.2）\n'
fi
printf '\n'

FAILED=0
TOTAL=0
PAC_LIST=        # phase=A 用例的 pac 观测，形如 `u1:0c8 u4:0c8 u4:0c8`
PAC_N=0

# ---------------------------------------------------------------- 逐例执行
# expect.csv 的行序就是执行序；跳过 # 注释与表头
while IFS=, read -r name expect words phase; do
    case "$name" in
        ''|'#'*) continue ;;
        case) continue ;;      # 表头
    esac
    TOTAL=$((TOTAL + 1))

    elf="$OUT/lib/$name.elf"
    sig="$OUT/$name.sig"
    log="$OUT/$name.log"
    rm -f "$sig"

    if [ ! -f "$elf" ]; then
        printf '%-10s FAIL  期望的 ELF 不存在：%s\n' "$name" "$elf"
        printf '%s,%s,%s,%s,%s,%s\n' "$name" "NA" "NA" "NA" "$expect" 0 >> "$CSV_TMP"
        FAILED=$((FAILED + 1))
        continue
    fi

    # ⛔ 不传 --inst-limit：L1 判据要求程序自己退出（陷阱 6：截断后 rc=0 看不出 HTIF 没工作）
    timeout "$TIMEOUT_SECS" "$SIM" -T "$sig" -g 8 "$elf" > "$log" 2>&1
    rc=$?

    trap_n=$(grep -c 'trapping' "$log" 2>/dev/null || true)
    [ -n "$trap_n" ] || trap_n=0
    # words 列＝这条用例的判据占几个字（预检已保证与 expect 字段数一致）。
    # ⚠️ expect=`-`（不作签名判据）时**仍然读首字**：读了才看得出"签名区是空的/没写"，
    #    才和上一轮记录同一形态；只是不拿它判 pass。
    if [ "$expect" = "-" ]; then want=0; else want=$words; fi
    got=$(get_sig "$sig" "$words")

    # 判据顺序照 §四：rc → HTIF 自退出 → trap → 签名（前者失败时后者无意义，但仍全列出来）
    reason=
    if [ "$rc" -eq 124 ]; then
        reason="超时 ${TIMEOUT_SECS}s 未自行退出（L1 陷阱 6）"
    elif [ "$rc" -ne 0 ]; then
        reason="rc=$rc（§四 判据 1）"
    elif ! grep -q 'HTIF located at 0x80003000' "$log"; then
        reason="没打印 'HTIF located at 0x80003000'（§四 判据 2）"
    elif [ "$trap_n" -ne 0 ]; then
        reason="trap=$trap_n（§四 判据 3）"
    elif [ "$expect" != "-" ] && [ "$(nfields "$got")" != "$want" ]; then
        reason="签名位数不符（§四 判据 4）：期望 $want 个字，实测 $got"
    elif [ "$expect" != "-" ] && [ "$(norm "$got")" != "$(norm "$expect")" ]; then
        reason="签名不符（§四 判据 4）：期望 $expect，实测 $got"
    fi

    if [ -z "$reason" ]; then
        pass=1
    else
        pass=0
        FAILED=$((FAILED + 1))
    fi

    printf '%s,%s,%s,%s,%s,%s\n' "$name" "$rc" "$trap_n" "$got" "$expect" "$pass" >> "$CSV_TMP"

    # ⭐ 跨用例守门（`m2-baseline.md` §6.3）：对**每个 Aligned 形态**的实测字记 pac（`bits 56..48`）。
    #    ⛔ 不逐条判 pac 的具体值（那是派生量，阶段 B 会变）；只判"一次运行里全部为 0"。
    #    取子集按 bit63（实测形态），⛔ 不按 phase 列 —— 否则阶段 B 摘掉 phase 时守门会失效。
    if [ "$expect" != "-" ]; then
        for w in $(printf '%s' "$got" | tr '/' ' '); do
            ww=$(printf '%s' "$w" | tr 'A-F' 'a-f' | sed 's/^0x//')
            [ "${#ww}" -eq 16 ] || continue
            is_aligned "$ww" || continue
            PAC_LIST="${PAC_LIST}${PAC_LIST:+ }$name:$(pac_of "$ww")"
            PAC_N=$((PAC_N + 1))
        done
    fi
    if [ "$pass" -eq 1 ]; then
        printf '%-10s PASS  rc=0 trap=0 sig=%s\n' "$name" "$got"
    else
        printf '%-10s FAIL  %s\n' "$name" "$reason"
        printf '           实测 sig=%s  expect=%s  log=%s\n' "$got" "$expect" "$log"
    fi
done < "$EXPECT_CLEAN"

[ "$TOTAL" -gt 0 ] || die "expect.csv 里一条用例都没读到（$EXPECT_FILE）"

# ---------------------------------------------------------------- 跨用例守门
# `m2-baseline.md` §6.3：一次运行里**所有** phase=A 用例的 pac 不得全为 0。
# 单条 pac=0 可能是真随机撞上（2^-9），⛔ 不判；**全部为 0** 只能是"没加签"。
# 这是**套件级**判据，所以它不改任何单条 case 的 pass，而是让整轮 rc=1。
PAC_ALL_ZERO=0
if [ "$PAC_N" -gt 0 ]; then
    all_zero=1
    for e in $PAC_LIST; do
        case "$e" in
            *:000) ;;
            *)     all_zero=0 ;;
        esac
    done
    [ "$all_zero" -eq 1 ] && PAC_ALL_ZERO=1
fi

# ---------------------------------------------------------------- 产物
mv "$CSV_TMP" "$OUT/m2.csv" || die "写不了 $OUT/m2.csv"
if [ -n "$CSV" ]; then
    cp "$OUT/m2.csv" "$CSV" || die "写不了 CSV：$CSV"
fi

{
    printf 'model_sha=%s\n' "$MODEL_SHA"
    printf 'arch_sha=%s\n' "$ARCH_SHA"
    printf 'sim=%s\n' "$SIM"
    printf 'sim_bytes=%s\n' "$SIM_SIZE"
    printf 'cases=%s\n' "$TOTAL"
    printf 'failed=%s\n' "$FAILED"
    printf 'timeout_secs=%s\n' "$TIMEOUT_SECS"
    # ⭐ 起止时间＋耗时：`D-182` §六.1 要求"复制不出来的那种"字段。
    #    复制一份 meta.txt 会连时间一起复制，但与文件 mtime／两份耗时的一致性对不上。
    printf 'started_at=%s\n' "$STARTED_AT"
    printf 'finished_at=%s\n' "$(date '+%Y-%m-%d %H:%M:%S.%N %z')"
    printf 'duration_s=%s\n' "$(awk -v a="$START_EPOCH" -v b="$(date +%s.%N)" 'BEGIN{printf "%.3f", b-a}')"
    printf 'phase_a_cases=%s\n' "${PHASE_A_CASES:--}"
    # 跨用例守门（§6.3）的现场：逐条 pac 值 ＋ 全零判定
    printf 'pac_observed=%s\n' "${PAC_LIST:--}"
    printf 'pac_all_zero=%s\n' "$PAC_ALL_ZERO"
    printf 'timeout_cmd=%s\n' "$(command -v timeout)"
    printf 'host=%s\n' "$(uname -sr)"
} > "$OUT/meta.txt"

printf '\n%d/%d 通过；CSV=%s\n' "$((TOTAL - FAILED))" "$TOTAL" "$OUT/m2.csv"
[ -n "$CSV" ] && printf '归档 CSV=%s\n' "$CSV"
if [ "$PAC_N" -gt 0 ]; then
    printf '跨用例守门（§6.3）：pac 观测 = %s ⇒ %s\n' "$PAC_LIST" \
        "$([ "$PAC_ALL_ZERO" -eq 1 ] && echo '❌ 全部为 0（没加签）' || echo '非全零 ✅')"
fi

if [ "$FAILED" -ne 0 ]; then
    printf '\nFAILED: %d 例未过（首因见上，逐例日志在 %s/）\n' "$FAILED" "$OUT"
    exit 1
fi

if [ "$PAC_ALL_ZERO" -eq 1 ]; then
    printf '\nFAILED: 跨用例守门（m2-baseline.md §6.3）—— 所有 phase=A 用例的 pac 全为 0\n'
    printf '        ⇒ 只能是"没加签"（单条 0 可能是 2^-9 撞上，全部 0 不是偶然）\n'
    printf '        ⛔ 不许改期望值绕过；报开发组，抄送架构组\n'
    exit 1
fi

printf 'M2 基线成立。\n'
exit 0
