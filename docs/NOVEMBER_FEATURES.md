# MoonH5 十一月功能扩展

应用需要跨工具读取分层数组、属性和规则切片，并在采集布局与消费布局之间转换。项目读取真实 HDF5，保留整数与浮点位，新增轴适配和数据批次拼接，使科研及应用数据可以直接交给后续分析器，核心不链接 libhdf5。

## 1. 多维轴置换

`ArrayValue::transpose`：接受完整无重复的轴排列，把行优先存储按新维度重排；按原始字节搬运，不将Int64/UInt64转浮点，保留数据类型、字节序和样本位。拒绝重复/越界轴。

复杂度与代价：O(E·rank+字节数) 时间、O(输出字节+rank)空间；零长度数组不生成无效stride；受元素和字节预算限制。

## 2. 兼容数组按轴拼接

`ArrayValue::concat_axis`：沿指定轴合并数组，严格要求相同datatype/byte order及其他轴extent，不做隐式类型转换；检查合并后维度、元素和字节数，结果可正常写回HDF5。

复杂度与代价：O(输出字节+rank)时间与O(输出字节)空间；不修改源数组，也不是文件就地扩展或压缩chunk写出。

## 运行

```sh
moon run examples/november --target native --deny-warn
moon check --target all --deny-warn
moon build --target all --deny-warn
moon test --target all --deny-warn
```

Windows当前工具链路径问题沿用README的项目适配脚本；源代码临时命名空间尚未发布。

## 范围

不完整支持任意 HDF5、VLEN/compound、全部chunk索引、压缩写出、resize、SWMR；不自动保证MATLAB7.3、NetCDF-4或Keras上层语义。数组内部表示已封装，直接读旧内部字段的代码需改用公开访问器。

h5py双向文件/链接/属性验证；新增轴置换、按轴拼接和三轴全排列坐标对照测试。 具体当前执行结果由本地检查记录提供，不以CI配置代替远端成功记录。
