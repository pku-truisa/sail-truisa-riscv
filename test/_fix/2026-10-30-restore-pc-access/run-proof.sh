#!/bin/sh
# 修复证明（D-175／D-180 §四 判据 4）—— pc_access 整份恢复至 72a56e9
#
# 断言对象是「**我这个改动是否达到了我声称的效果**」，不是「什么算对」：
#   声称的效果 = ① 文件逐字节等于上游 72a56e9
#                ② set_next_pc 的 convertInvalidAddr 钩子清零
#                ③ 文件里没有任何 PCC／nextPCC／Capability 残留
#                ④ val 声明数 = 4（force_pc 那条按 D-180 §三 不补，是 A 的代价）
#
# ⛔ 本脚本**不含**行为断言：M2 三签名归**测试组**（D-180 §四 判据 3），
#    本组不重复跑、不代替其裁定。签名若有变，是"零行为变化"不成立的信号。
#
# 用法（模型仓根目录）：sh test/_fix/2026-10-30-restore-pc-access/run-proof.sh
# 退出码：0 全部断言成立 ／ 1 有断言不成立 ／ 2 环境问题（不在模型仓／取不到上游 blob）

set -u
UP=72a56e9
F=model/riscv_pc_access.sail

git rev-parse --git-dir >/dev/null 2>&1 || { echo "ERROR: 不在 git 树里" >&2; exit 2; }
want=$(git rev-parse "$UP:$F" 2>/dev/null) || { echo "ERROR: 取不到 $UP:$F" >&2; exit 2; }
got=$(git hash-object "$F") || exit 2

fail=0
chk() { printf '%-40s %s\n' "$1" "$2"; }

[ "$want" = "$got" ] \
  && chk "1 逐字节=上游 72a56e9" "PASS （blob $got）" \
  || { chk "1 逐字节=上游 72a56e9" "FAIL （want $want / got $got）"; fail=1; }

n=$(grep -c convertInvalidAddr "$F" 2>/dev/null || true); n=${n:-0}
[ "$n" -eq 0 ] \
  && chk "2 convertInvalidAddr 残留" "PASS （0）" \
  || { chk "2 convertInvalidAddr 残留" "FAIL （$n 处）"; fail=1; }

n=$(grep -cE '\b(PCC|nextPCC|Capability)\b' "$F" 2>/dev/null || true); n=${n:-0}
[ "$n" -eq 0 ] \
  && chk "3 PCC/nextPCC/Capability 残留" "PASS （0）" \
  || { chk "3 PCC/nextPCC/Capability 残留" "FAIL （$n 处）"; fail=1; }

n=$(grep -c '^val ' "$F" 2>/dev/null || true); n=${n:-0}
[ "$n" -eq 4 ] \
  && chk "4 val 声明数（force_pc 无 val）" "PASS （4）" \
  || { chk "4 val 声明数（force_pc 无 val）" "FAIL （$n）"; fail=1; }

echo
if [ "$fail" -eq 0 ]; then
  echo "本改动的声称效果全部成立。⚠️ 行为等价（M2 三签名）由测试组判（D-180 判据 3）。"
  exit 0
fi
echo "有断言不成立 —— 停下回函，⛔ 不许改期望值迁就。"
exit 1
