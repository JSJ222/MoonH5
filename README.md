# MoonH5

纯 MoonBit 的、有明确兼容边界的 HDF5 数组读写库。无需安装或链接 C `libhdf5`，核心支持 native、JavaScript、Wasm 与 Wasm-GC。它处理真实 HDF5 字节，而不是以自定义 JSON 代替 HDF5。

适合仪器数据交换、仿真结果切片、固定形状训练数据和参数数组，以及 Web/WASM 中的离线科学数据处理。它不是完整 HDF5 实现，也不自动保证兼容 MATLAB v7.3、NetCDF-4、Keras 等上层格式。

模块：`JSJ222/moonh5@0.1.0`；[GitHub](https://github.com/JSJ222/MoonH5) · [Mooncakes](https://mooncakes.io/docs/JSJ222/moonh5)。

## 安装与复现

安装 [官方 MoonBit 工具链](https://docs.moonbitlang.com/en/latest/download-and-install.html)，已验证 `moonc 0.10.16`，CI 固定 compiler/core 0.10.16+b1a0e846e。进入此项目目录后：

```sh
moon version --all
moon check --target all --deny-warn
moon build --target all --deny-warn
moon test --target all --deny-warn
moon run examples/instrument
moon run examples/simulation
moon run examples/training
moon run examples/scale --target native --release
```

依赖版本已写入 `moon.mod`，工具链按需解析。核心 API 除纯 MoonBit DEFLATE 库外无平台依赖；原生 CLI 使用官方 async 文件 API。当前 Windows Moon 20261016 的 OCaml 子进程可能不接受 `\\?\` 路径，可使用随项目提供的参数适配器：

```powershell
.\tools\windows\moon.ps1 check --target all --deny-warn
.\tools\windows\moon.ps1 test --target all --deny-warn
.\tools\windows\moon.ps1 run examples/instrument
```

适配器首次运行需 MSVC Build Tools；只生成 `_build` 内容和临时进程环境，不替换官方编译器，也不修改系统配置。

## 最小 API 示例

在已有 MoonBit 工程中安装：

```sh
moon add JSJ222/moonh5@0.1.0
```

在使用方 `moon.pkg` 中配置 `import { "JSJ222/moonh5" @h5, }`；以下代码可直接运行，完整场景见 `examples/instrument`。

```moonbit
fn main raise {
  let doc = @h5.Document::new()
  let values = @h5.ArrayValue::from_floats(
    Simple([2, 3]), [1.0, 2.0, 3.0, 4.0, 5.0, 6.0],
  )
  doc.add_dataset("/samples", values)
  doc.set_attribute("/samples", "units",
    @h5.ArrayValue::from_strings(Scalar, ["K"], 1))
  let file = @h5.H5File::open(doc.encode())
  let selection = @h5.Selection::new(Simple([2, 3]), [
    { start: 1, stride: 1, count: 1, block: 1 },
    { start: 0, stride: 2, count: 2, block: 1 },
  ])
  assert_eq(file.read_selection("/samples", selection).float_at(1), 6.0)
}
```

`ArrayValue::new` 接收定宽原始字节和显式字节序；`from_signed/from_unsigned/from_floats` 分别产生 64 位数据。定宽 UTF-8 字符串按字节宽度校验，不截断字符。`with_byte_order` 只交换字节序，保留 NaN payload 和整数全部位；`with_selection` 返回新数组，不修改输入。

## 兼容范围

| 子系统 | 支持 | 明确不支持 |
| --- | --- | --- |
| 文件 | superblock 0/1/2/3、标准 user block、2/4/8 字节地址/长度；v2/3 校验和 | SWMR/活动写入、多文件驱动、superblock 扩展 |
| 对象与组 | v1/v2 对象头与继续块；旧符号表、compact links；硬链接别名/环和软链接 | dense groups/fractal heaps、外部链接、共享/提交类型 |
| 数组 | scalar、simple、null 和零长度维；连续、紧凑、旧 v1 B-tree 分块；现代未分页 fixed-array 分块 | paged fixed-array、single/implicit/extensible/v2 B-tree 索引、VDS、resize |
| 类型 | 8/16/32/64 位整数、IEEE32/64、定长 ASCII/UTF-8；大小端 | VLEN、compound、enum、reference、opaque、非标准浮点 |
| 属性 | 内联 v1/v2/v3 定宽数组属性 | dense/shared 属性 |
| 过滤器 | gzip（实际为 zlib 封装 DEFLATE）、shuffle、Fletcher32；逐块 filter mask | LZF、SZIP、插件、scale-offset；部分边界块跳过滤器布局标志 |
| 写出 | 新建确定性 superblock2/object-header2、compact groups、连续/紧凑定宽数组、属性、硬/软链接 | 分块/压缩写出、就地修改、保留未知消息或物理布局 |

fixed-array 仅接受当前网格与索引最大网格一致的未分页索引。superblock1 解析入口存在，但独立 h5py 样例主要验证 0/2/3；不将入口存在等同于任意变体均验证。文件打开只验证入口及根对象，其余对象按访问校验。

`to_document()` 将受支持数据语义化重新打包，保留数组、属性及链接关系，不承诺保留字节布局、过滤器、对象时间戳、注释或所有创建属性。不支持的类型、组、存储和属性会报错；不要用它无损复制任意第三方文件。路径不接受 `..`，重叠 hyperslab block 也会明确拒绝。

## 原生文件工具

```sh
moon run cmd/main --target native -- write-demo NEW.h5
moon run cmd/main --target native -- read INPUT.h5
moon run cmd/main --target native -- repack INPUT.h5 NEW.h5
```

写入均使用 `CreateNew`，不会覆盖已有文件。`read` 输出 JSON 清单及数组值，适合小文件检验；整数使用十进制字符串，非有限浮点及负零使用字符串，避免 JSON 丢失语义。大数组请使用库的选择 API，而不是输出全部 JSON。文件读取由调用方负责；库接受内存字节，不会自行访问网络、外部文件或软链接指向的操作系统路径。

## 测试与互操作

`moon test --target all --deny-warn` 包含原子类型边界、规则块选择、损坏/截断、资源限制、链接环、独立 h5py 样例、稀疏/边界分块与过滤器回归。[Linux/Windows GitHub Actions](https://github.com/JSJ222/MoonH5/actions) 覆盖四后端检查、构建、测试、格式、公共 API、五个场景、独立互操作与打包卫生；工程检查不等于正式赛事验收。

独立双向对照（Python 仅用于开发测试，不是库运行依赖）：

```sh
python -m venv _local/venv
# 激活虚拟环境后
python -m pip install -r scripts/requirements-interop.txt
moon build --target native --deny-warn
python scripts/interop.py verify _build/native/debug/build/cmd/main/main.exe
python scripts/verify_repository.py
```

Windows 使用 `_local\venv\Scripts\python.exe`，Moon 命令可改为上述 Windows 适配器。脚本验证 h5py→MoonH5、MoonH5→h5py、重新打包、别名/属性及禁止覆盖。`fixtures/*.h5` 均由 `scripts/interop.py generate fixtures` 原创生成；`scripts/embed_fixtures.py` 将其转换为跨后端测试字节，再运行 `moon fmt`。生成字节数据不计入有效代码行数。

## 安全、复杂度与边界

默认限制：文件/输出 256 MiB，单数组 16,777,216 个元素，单对象元数据 16 MiB，遍历对象/链接及分块数量 100,000，深度 64，rank 32。可通过 `Limits` 收紧；安全限制不是整个进程的精确峰值内存上限，输入、解码缓存和输出可同时存在。所有文件下标必须适合 MoonBit Int，超过约 2 GiB 的地址/维度会拒绝。

连续切片将相邻单元合并为读取跨度；分块切片只解码命中的块，但输入文件当前仍整体位于内存，索引也会遍历。选择映射约为 O(E×rank)，缓存 O(命中块字节)，索引 O(块数)。写出一次建立邻接索引，排序约 O(N log N)，序列化 O(元数据+数据字节)，不再逐组扫描全部节点。`examples/scale` 是可复现正确性负载，不代表与 C HDF5 的性能比较。

## 来源、许可证与维护

核心按 [HDF Group 文件格式规范](https://portal.hdfgroup.org/documentation/hdf5/latest/_f_m_t3.html) 独立实现，不是 pyfive/jsfive 的代码移植；元数据 lookup3 算法来源与依赖见 [THIRD_PARTY.md](THIRD_PARTY.md)。核心 MIT，复用的 Windows 工具保留 Apache-2.0。开发使用 AI 辅助，代码行为由测试和独立工具检验；使用者仍需根据实际数据与风险验证兼容性。

领域词汇见 `CONTEXT.md`，设计取舍见 `docs/adr/`，公开接口见 `pkg.generated.mbti`。后续优先维护真实互操作缺陷；新编码需独立 fixture 和明确边界后才加入。申报书、审查与 AI 辅助材料不属于公共工程文档，可在项目本地文件夹保存，通过忽略及历史/包检查排除，不进入 Git 或发行包。


## 十一月新增功能

**多维轴置换**（`ArrayValue::transpose`）；**兼容数组按轴拼接**（`ArrayValue::concat_axis`）。详见[功能、用途和边界](docs/NOVEMBER_FEATURES.md)，运行 `moon run examples/november --target native --deny-warn`。功能包含于0.1.0，安装方式见上文。


## 本地开发增量（未发布）

新增 **无损形状重排**、**有序轴采样 gather**，用途、限制和复杂度见 [功能文档](docs/EXPANSION_20261106.md)。
从本仓库源码运行 `moon run examples/expansion --target native --deny-warn`。
本节 API 尚未包含在已发布的 0.1.0 中。
