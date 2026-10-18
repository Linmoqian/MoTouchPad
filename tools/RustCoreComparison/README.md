# Swift / Rust 核心对照

独立 SwiftPM 工具，macOS 13+。需要 Xcode Command Line Tools 和 Rust，版本与设备信息记录在评估报告中。先构建 Rust 静态库，再构建 Swift 可执行程序。

```sh
bash tools/RustCoreComparison/run.sh         # 3 轮，每轮 51 个采样块，每块回放 64 次
bash tools/RustCoreComparison/run.sh 1 3     # 快速正确性和构建检查
bash tools/RustCoreComparison/run.sh --skip-build 64 51 # 确认源码未变时复用已构建二进制
python3 tools/RustCoreComparison/summarize.py # 校验跨进程校验和并汇总三轮结果
```

脚本先运行 Rust 测试，再进行逐步行为对照与 Release 微基准。使用仓库 `MoTouchPadCore` 库和真实 C ABI，不注入 CGEvent。每轮检查共享轨迹、固定种子压力轨迹、协议黄金样例及全部分片位置。结果写入忽略的 `results/`，源码与固定输入入库。

测量路径：

| 路径 | 计时范围 |
|---|---|
| swift-native | Swift 解码完整帧、状态机和动作校验和 |
| rust-native | Rust 解码相同完整帧、状态机和动作校验和 |
| swift-rust-raw | Swift 借用 Data、C 调用、Rust 解码/状态机、复制固定动作缓冲和校验和 |
| swift-rust-adapted | raw 路径加转换为现有 `[GestureAction]` 和同一 Swift 校验和 |
| c-abi-noop-loop | Swift 循环调用 C 恒等函数；含循环/累加，仅估算空调用成本 |

四条业务路径均在每个步骤后读取计时截止时间，跨语言路径因此包含推进和查询两次调用。计时不含载入文件、解析十六进制、首次建句柄、协议编码、正确性对照、计时任务调度、网络收发或系统输入。每个输入步骤（包括 reset、smart、advance、flush）算一次操作。每条性能路径先预热八次。原生 Rust 保留整个动作输出以避免无用计算被优化；三个业务路径和原生 Rust 使用相同的整数动作校验和，逐步比较另行检查位移浮点数（容差 1e-6）和计时截止时间（1e-9 秒）。

P95/P99 指每个采样块的平均 ns/op 分布，不代表单帧尾延迟。不要用此基准推算 Wi-Fi、屏幕显示或用户手感。执行顺序第二轮交换，路径保持串行；后台负载和功耗状态仍会影响结果。报告采用各轮中位数的中位数。

可以直接运行 `.build/release/CompareCore ROOT OUTPUT REPEATS SAMPLES` 复查，输出文件路径应可写。异常会返回非零退出状态。`run.sh` 使用 SwiftPM 创建的 `.build/release` 架构链接；复用模式应先确认两套产物对应当前源码，它仍会执行完整正确性对照和跨进程校验。
