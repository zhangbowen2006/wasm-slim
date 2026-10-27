# WasmSlim

体积诊断与安全裁剪工具，面向 MoonBit 编译产出的 WebAssembly 模块。

MoonBit 的 debug 构建里，**约 60% 的字节是自定义段**（名字表、调试信息）。这些字节对运行没有贡献，却直接进入浏览器首屏下载与边缘冷启动路径。WasmSlim 把体积按段拆开告诉你花在哪，并安全地裁掉不该上线的那部分。

## 实测

对一个 40 KB 的真实 MoonBit 产物：

```
$ moon run cmd -- build/cmd.wasm
size    39.6 KiB (40603 bytes)
sections 13
  id=1  128 B   0%     type
  id=2  740 B   1%     import
  id=3  163 B   0%     function
  id=7  20 B    0%     export
  id=10 13.4 KiB 33%   code
  id=11 1.2 KiB  3%    data
  id=0  23.7 KiB 59%   custom (names/debug)
  id=0  69 B    0%     custom

functions  imported=17 defined=161 total=178
reachable  178
unreachable 0

$ moon run cmd -- build/cmd.wasm --strip
before     39.6 KiB (40603 bytes)
after      15.8 KiB (16227 bytes)
saved      23.8 KiB (60%)
```

裁剪后的模块通过标准验证器：`WebAssembly.validate(stripped) === true`。

## 用法

```sh
# 体积诊断
moon run cmd -- path/to/module.wasm

# 删除自定义段（名字/调试信息），输出到新文件
moon run cmd -- path/to/module.wasm --strip
moon run cmd -- path/to/module.wasm --strip --out slim.wasm

# 定位指令扫描失败的位置（开发用）
moon run cmd -- path/to/module.wasm --debug
```

## 它做了什么

- **段级归因**：遍历 section 表，输出每个段的字节数与占比，包括多个 custom 段。
- **指令扫描**：解析函数体，识别 `call` / `ref.func` / `call_indirect`，覆盖控制流、内存访问、SIMD（`0xFD`）、批量内存（`0xFC`）、引用类型与 GC 前缀。遇到不认识的字节就停止并报告位置，不猜测。
- **可达性分析**：以导出、`start`、element 段为根做广度优先遍历。element 段的八种 flag 形式全部处理，包括 `ref.func` 表达式形式（flags 4–7）——漏掉它们会把仍在使用的函数误判为死代码。
- **安全裁剪**：复制除 custom 以外的所有段，保留原始长度前缀。

## 边界（先说清楚）

- **不重写函数索引**。删除函数需要重编号 `call`、`ref.func`、`export`、element 与 code 段，当前版本不做这件事；因此裁剪只发生在段级。
- **对 MoonBit 产物，死代码分析的结果是 0**。实测 debug 与 release 构建均为 0——编译器自己已经做了消除。死代码分析的用处在第三方或手写模块。
- **不删除未使用的全局/表/数据段**。
- **不是链接器**，不合并多个模块。

## 构建与测试

```sh
moon check --deny-warn
moon test --deny-warn     # 9 个单元测试：LEB128 往返、段遍历、magic 校验、可达性判定、导出解析、裁剪保真
moon build --target wasm  # 用本仓库自身产物做端到端样本
```

## 许可

MIT。依赖 `moonbitlang/core`（Apache-2.0）与 `moonbitlang/x`（Apache-2.0），许可证与声明随项目分发。
