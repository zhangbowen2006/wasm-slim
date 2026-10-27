# WasmSlim
### MoonBit Wasm 产物的体积诊断与安全裁剪

| 项目 | 内容 |
| --- | --- |
| 参赛者 | 张博文（GitHub：`zhangbowen2006`） |
| 联系方式 | 15614198610｜1161915493@qq.com |
| 参赛方向 | 新项目申报—参与季度评选 |
| 许可证 | MIT |
| GitHub 仓库 | https://github.com/zhangbowen2006/wasm-slim |
| CI | https://github.com/zhangbowen2006/wasm-slim/actions |

## 一、项目简介

WasmSlim 是使用 MoonBit 编写的 WebAssembly 模块体积诊断与裁剪工具，面向所有把 MoonBit 编译到 Wasm 的部署场景。它解析模块的段表与函数体，按段给出体积归因，指出「这些字节花在哪里」；并安全地删掉对运行没有贡献的部分，输出仍能通过标准验证器的模块。

与只报总体积的做法不同，WasmSlim 打开到函数级：解析每一段指令，识别调用关系与间接调用目标，判断哪些函数真的会被执行；裁剪时只做能证明安全的操作，遇到无法解析的字节就停止并报告位置，不猜测。

## 二、要解决的问题

一个 40 KB 的 MoonBit 产物，体积分布是这样的：

```text
id=10  code      13.4 KiB  33%
id=11  data       1.2 KiB   3%
id=0   custom    23.7 KiB  59%   <- 名字表与调试信息
id=0   custom      69 B      0%
```

**接近六成的字节是调试信息**，它们对运行没有贡献，却会进入浏览器首屏下载与边缘冷启动路径。WasmSlim 的输出：

```text
before     39.6 KiB (40603 bytes)
after      15.8 KiB (16227 bytes)
saved      23.8 KiB (60%)
```

裁剪后的模块 `WebAssembly.validate()` 返回 true，代码段、类型段、导出段一个字节没动。

## 三、核心能力

| 能力 | 说明 |
| --- | --- |
| 段级归因 | 遍历段表，输出每段字节数与占比，多个 custom 段分别列出 |
| 指令扫描 | 覆盖控制流、内存访问、SIMD（`0xFD`）、批量内存（`0xFC`）、引用类型与 GC 前缀；未知字节立即停止并报告位置 |
| 可达性分析 | 以导出、`start`、element 段为根做 BFS；element 段的八种 flag 形式全部处理，含 `ref.func` 表达式形式 |
| 安全裁剪 | 复制除 custom 外的所有段，保留原始长度前缀；不重排索引 |
| 失败关闭 | 解析失败或存在未知操作码时不输出裁剪结果，只报告 |
| 自举测试 | 用本仓库自身的 Wasm 产物作为端到端样本 |

## 四、三个完整用例

### 1. 发布前瘦身

- **输入**：MoonBit 的 release 产物 31 KB。
- **输出**：`--strip` 后体积下降，模块仍通过标准验证器。
- **价值**：不需要改构建脚本，不需要引入二进制工具链，一条命令完成。

### 2. 体积归因

- **输入**：任意 Wasm 模块。
- **输出**：按段列出字节数与占比，指出「code 占 33%、custom 占 59%」。
- **价值**：先知道该优化什么，再决定是否裁剪；避免盲目压缩。

### 3. 第三方模块的死代码检查

- **输入**：非 MoonBit 编译器产出的模块。
- **输出**：可达/不可达函数统计，不可达函数的索引与函数体字节数。
- **价值**：MoonBit 自己的产物死代码为 0（实测），但手写或第三方模块常有未使用的导出，这里能给出量化结果。

## 五、与已有项目的关系

| 项目 | 定位 | 与 WasmSlim 的边界 |
| --- | --- | --- |
| `BigSaltyMan/moonsize` | Wasm 体积剖析，按段统计 | WasmSlim 在归因之外做裁剪，且解析到函数级可达性 |
| `mizchi/wite` | 组件模型感知的 Wasm 分析 | WasmSlim 不处理 Component Model，专注核心模块与裁剪输出 |
| `PerfectPan/svgo` | SVG 优化器 | 不同格式，无交集 |

WasmSlim 与上述项目**无代码复用，不是任何项目的分支、改名或扩展**；Wasm 二进制解析、指令扫描、可达性与裁剪均为独立实现，仅依赖 `moonbitlang/core` 与 `moonbitlang/x`。

## 六、验证与交付

- **测试**：5 项 MoonBit 单元测试（LEB128 往返、段遍历、magic 校验、裁剪保真）。
- **实测**：40603 字节 → 16227 字节（-60%）；输出通过 `WebAssembly.validate`。
- **CI**：Linux 上执行 check、test、构建真实 Wasm 样本、裁剪并用 Node 标准验证器校验。
- **可复核**：`moon run cmd -- <file.wasm>`（归因）、`moon run cmd -- <file.wasm> --strip`（裁剪）。

## 七、技术边界与许可

只做段级裁剪，不重写函数索引（删除函数需要重编号 `call`、`ref.func`、`export`、element 与 code 段，当前版本不做）；不删除未使用的全局、表与数据段；不是链接器，不合并模块；对 MoonBit 产物的死代码分析结果为 0，该能力的用处在第三方模块。

原创代码采用 MIT License；示例数据为合成样本与本仓库自身产物；依赖 `moonbitlang/core`、`moonbitlang/x`（均为 Apache-2.0），许可证与声明随项目分发；无移植代码。
