# MoonH5 增量功能：2026-11-06

状态：本页 API 已纳入0.2.0，可安装 JSJ222/moonh5@0.2.0 或使用本目录源码。

## 无损形状重排与有序轴采样 gather
`ArrayValue::reshape(space, limits~)` 在元素数量一致时修改 dataspace，保留原始字节、类型和字节序。
Scalar 与 Simple([1]) 可互换；Null 仅能变为 Null，不与零元素 Simple 混同。
零元素 Simple 可以重排为其他零元素 Simple，仍受 rank、维度、元素和字节预算检查。

`ArrayValue::take_axis(axis, indices, limits~)` 对 Simple dataspace 的指定轴按调用顺序采样。
支持重复索引、反序和空选择；保留其他维度，输出所选轴长度为 indices.length()。
按连续内部块复制原始字节，不经 Double 中转，UInt64 最大值、NaN payload、大小端均保留。
拒绝越界/负索引、无效轴、Scalar/Null gather，分配前校验元素与字节上限。
输出为独立值，不修改输入的形状、索引数组或样本。

用于传感器通道重排、训练数据特征选择、科学数组展开和 HDF5 数据导出适配。
这些是内存数组运算，不宣称 HDF5 磁盘层零拷贝或 NumPy 的所有高级索引语义。

reshape 时间/空间 O(rank)，共享不可变 Bytes；gather 时间 O(B+rank+I)、空间 O(B+rank)，
B 为输出字节、I 为索引数量。零元素输出跳过内部 stride 计算，避免无意义乘积溢出。
测试包含 3D 各轴独立坐标 oracle、重复/空/非法索引、Scalar/Null、UInt64 大端精度及 HDF5 往返。

## 运行

```sh
moon run examples/expansion --target native --deny-warn
moon test --target all --deny-warn
```

Windows 使用 README 中对应的 Moon 包装脚本替代 `moon`。
CI 已添加该示例；无需网络服务、私钥或真实设备。
