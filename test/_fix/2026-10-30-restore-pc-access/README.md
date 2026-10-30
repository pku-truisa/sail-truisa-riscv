# 修复证明 —— `riscv_pc_access.sail` 整份恢复至 `72a56e9`（`D-180` 裁 A）

> 制度：`D-175`（修复证明）｜单据：`D-180` §四 判据 4｜日期：2026-10-30
> ⚠️ **本目录是临时的、⛔ 不进回归基线**。是否吸收由**测试组**定（`D-175` §2.4）；被吸收者的期望值由**架构组**写。

## 一、这个改动声称的效果（断言的对象是「我的改动」）

| # | 声称 | 为什么它能被独立复核 |
|---|---|---|
| 1 | 文件**逐字节**等于上游 `72a56e9` 的那份 | blob 相等即可判，与人无关 |
| 2 | `set_next_pc` 的 `convertInvalidAddr` 钩子**清零** | 该点在本链是恒等（`riscv_convert_invalid_addr.sail`：`convertInvalidAddrBits(addr) = addr`）⇒ 删它零行为变化 |
| 3 | 文件里**没有** `PCC`／`nextPCC`／`Capability` 残留（含注释） | 整份恢复后连 `D-168` 的说明注释也一起回上游形态 |
| 4 | `val` 声明数 = **4**（`force_pc` 那条**不补**） | 这是 A（整份恢复）的**代价**，`D-180` §三 已认账 |

## 二、复跑（一条命令）

```sh
sh test/_fix/2026-10-30-restore-pc-access/run-proof.sh     # 模型仓根目录
```

## 三、实测（`run-proof.sh` 输出，逐字）

```text
1 逐字节=上游 72a56e9               PASS （blob c302ad65497f98d29f0aeb403de512c19d468b31）
2 convertInvalidAddr 残留              PASS （0）
3 PCC/nextPCC/Capability 残留          PASS （0）
4 val 声明数（force_pc 无 val）    PASS （4）

本改动的声称效果全部成立。⚠️ 行为等价（M2 三签名）由测试组判（D-180 判据 3）。
```

| 项 | 期望 | 实测 | 判 |
|---|---|---|---|
| 工作区 `git hash-object` | = `72a56e9:` 的 blob | `c302ad65…68b31` = `c302ad65…68b31` | ✅ |
| `grep -c convertInvalidAddr` | 0 | 0（`grep` 零命中 ⇒ rc=1，不是命令坏） | ✅ |
| `grep -cE '\b(PCC\|nextPCC\|Capability)\b'` | 0 | 0 | ✅ |
| `grep -c '^val '` | 4 | 4 | ✅ |
| 行数／行尾 | 38 行、LF | 38 行、CRLF 命中 0（rc=1） | ✅ |
| `git diff` 形态 | 只该有 `set_next_pc`／`force_pc` 两处 | `3 insertions(+), 22 deletions(-)`，2 hunk | ✅ |

## 四、编译（`D-180` §四 判据 2）

| 项 | 值 |
|---|---|
| 命令 | `DOWNLOAD_GMP=FALSE bash build_emulators.sh` |
| 退出码 | **0** |
| 耗时 | **496 s**（8m16s，冷树；`M1` 那次 3m16.9s 有缓存，不可比） |
| 产物 | `build/c_emulator/sail_riscv_sim`，**19,275,744 B**，`sha256 7ea8027f…ecf2e` |
| Sail 侧 | `Type error` 0 ／ `not found` 0 ／ `already bound` 0 |
| C 侧 | 138 条 warning（绝大多数 `unused parameter`，既有），**无 error**；日志里 4 处 `error` 全是标识符名（`ext_fetch_addr_error` 等） |

环境：WSL2 `Linux 6.6.87.2-microsoft-standard-WSL2`（Ubuntu 22.04）／Sail **0.20.3**／gcc 11.4.0／cmake 3.22.1／`DOWNLOAD_GMP=FALSE`。
⚠️ 构建在 **WSL 原生盘**做的（`/home/td/build-pc-restore`），⛔ 不在 `/mnt/d`；⚠️ 字节数**不进判据**（`D-176`）。

⚠️ **踩到的坑（留给下一个人）**：建副本时 `rsync --exclude build` 会把
`dependencies/softfloat/berkeley-softfloat-3/build/` 一起过滤掉 ⇒ 依赖从 465 变 **445**，
构建时报的却是 `s_propagateNaNF128UI.c: platform.h: No such file`（看着像上游源码坏）。
✅ 必须锚定：`--exclude /build`。同一棵树的 `build_emulators.sh` 对这件事有断言，但它只在**那棵树里**生效，
**复制这一步在脚本之外** —— 所以这条只能靠人记。

## 五、⛔ 本证明**不**断言什么（边界）

| 不断言什么 | 归谁 |
|---|---|
| **M2 三签名不变**（`u1`／`u2`／`u3` 逐字节） | ⛔ **测试组**（`D-180` §四 判据 3）。本组**未跑** `test/m2/run.sh`，⛔ 不代替其裁定 |
| 架构语义是否应该这样改 | 架构组（`D-180` 已裁 A） |
| `A-8`（`convertInvalidAddr` 整族去留） | 架构组，仍待裁；本改动使调用点 **16 → 15** |

⚠️ 若测试组跑出的签名与 `docs/test/m2-baseline.md` 不一致 ⇒ **立刻停**，⛔ 不许以本证明"编译过了"掩盖（`D-180` 反方 1／2）。
