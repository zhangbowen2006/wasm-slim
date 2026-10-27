# WasmSlim

MoonBit Wasm 产物的**体积门禁与差分归因**。两个问题，两套答案：

- **能不能上线？** `--check` 给出 PASS/FAIL 和退出码，直接接 CI。
- **这次改动让包大了多少、大在哪个函数？** `--diff` 给出函数级增量。

```sh
moon run cmd -- build/app.wasm --check
```

```text
file      build/app.wasm
size      39.6 KiB (40603 bytes)
profile   debug (custom sections 60%)
dead code 0 function(s), 0 body bytes
budget    not set

  error  debug-build  looks like a debug build: custom sections are 60% of the file (24370 bytes). Ship a --release build, or strip the module.

verdict   FAIL
```

退出码 `1`，CI 直接红。同一份代码的 release 产物：

```text
profile   release (custom sections 0%)

  info  ok  no blocking issue found.

verdict   PASS
```

## 为什么需要它

同一份代码，两种构建的产物体积差 2.5 倍：

| 构建 | 大小 | custom 段 | 能否上线 |
| --- | --- | --- | --- |
| debug (wasm) | 40603 B | 55.0 KiB (57%) | **不该** |
| release (wasm) | 31706 B | 110 B (0%) | 可以 |
| release (wasm-gc) | 28220 B | 110 B (0%) | 可以 |

**debug 产物有六成是名字表和调试信息。** 忘记加 `--release`、或者为了线上排查而用 debug 产物发布，是一个真实发生的失误——这些字节会直接进入浏览器首屏下载和边缘冷启动。人工 review 看不出来，`:file` 命令也看不出来，但 `custom 段占比` 一眼就能看出。

WasmSlim 把这件事变成 CI 里的一条规则：**debug 构建直接失败**。它也支持体积预算，防止某次提交悄悄把包撑大。

## 用法

```sh
# 门禁：debug 构建或超预算时退出码为 1
moon run cmd -- app.wasm --check
moon run cmd -- app.wasm --check --budget 32768

# 体积归因：这些字节花在哪
moon run cmd -- app.wasm

# 需要时裁掉调试信息（debug 产物可减 60%）
moon run cmd -- app.wasm --strip --out slim.wasm
```

## 差分：这次改动大在哪个函数

```sh
moon run cmd -- new.wasm --diff old.wasm
```

```text
old       39.6 KiB (40603 bytes)
new       134.1 KiB (137338 bytes)
delta     +96735 bytes
functions old=161 new=308 added=158 removed=11

largest changes:
  +6676 B  ____moonbit__main  (586 -> 7262)
  +4635 B  zhangbowen20068wasmslim3src4wasm10scan__body  (0 -> 4635)
  +2521 B  zhangbowen20068wasmslim3src8analysis14element__roots  (0 -> 2521)
  +1890 B  zhangbowen20068wasmslim3src8analysis7analyze  (0 -> 1890)
```

函数名来自 `name` custom section 的函数名子段（调试构建自带）；没有名字段时退回 `func[<index>]` 并在输出里注明按索引对齐。匹配按函数名做，所以函数增删不会错位。

## 函数体积排行

```sh
moon run cmd -- app.wasm --top 10
```

```text
631 B  _M0FPB20int__to__string__dec
586 B  _M0FP017____moonbit__main
480 B  moonbit.utf8.encode_from_utf16
360 B  _M0FP414zhangbowen20068wasmslim3src4wasm9read__u32
```

## 审计规则

| 规则 | 级别 | 触发条件 |
| --- | --- | --- |
| `debug-build` | error | custom 段占比 ≥ 20%（实测 debug 为 57–60%，release 为 0%） |
| `over-budget` | error | 文件大小超过 `--budget` |
| `dead-code` | warn | 存在不可达函数（记录数量与函数体字节） |
| `ok` | info | 没有阻塞问题 |

退出码：`0` 通过，`1` 有 error，`2` 用法或解析错误。

## 支撑它的解析器

门禁的判定全部建立在自研的 Wasm 二进制解析上，不依赖外部工具：

- **段级遍历**：每个 section 的边界、大小、占比，多个 custom 段分别列出。
- **name section**：解析 custom 段里嵌套的子段，取出构造函数名表；子段越界时停止而不是读穿。
- **指令扫描**：解析函数体，识别 `call` / `ref.func` / `call_indirect`，覆盖控制流、内存访问、SIMD（`0xFD`）、批量内存（`0xFC`）、引用类型与 GC 前缀。遇到不认识的字节立即停止并报告偏移，不猜测。
- **可达性分析**：以导出、`start`、element 段为根做 BFS。element 段的八种 flag 形式全部处理，包括 `ref.func` 表达式形式——漏掉它们会把仍在使用的函数误判为死代码。
- **畸形输入**：段长度或名字越界时给出偏移与字节数，而不是崩溃堆栈。

## 边界（先说清楚）

- **对 release 构建，`--strip` 收益接近 0**（实测 −0.4%）。MoonBit 的 release 构建已经很紧凑，WasmSlim 的作用是确认这一点，不是假装还能压。
- **MoonBit 产物的死代码为 0**（debug 与 release 实测均为 0）。死代码规则对手写或第三方模块才有意义。
- **只做段级裁剪**，不重写函数索引（删除函数需要重编号 `call`、`ref.func`、`export`、element 与 code 段）。
- 不是链接器，不合并模块；不处理 Component Model。

## 构建与测试

```sh
moon check
moon test          # 18 个单元测试
moon build --target wasm
```

CI 会在 Linux 上跑完整链路：check → test → 构建真实 Wasm → 归因 → 门禁 → 裁剪 → 用 Node 的标准验证器校验输出。

## 许可

MIT。依赖 `moonbitlang/core`、`moonbitlang/x`（均为 Apache-2.0），许可证与声明随项目分发。
