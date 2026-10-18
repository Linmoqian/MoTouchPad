# 手势回放轨迹

`gestures-v1.trace` 是 Swift 与 Rust 共用的确定性输入，包含 37 个场景、569 个步骤。它使用 protocol v1 的原始帧，覆盖 1–4 指动作、5 指抑制、部分 UP、空快照取消、触点升级与 ID 替换、断连重置、延迟右键和停留计时。

每行四列，以 Tab 分隔：场景名、操作、接收端单调时间（秒）、参数。`frame` 参数为网络帧十六进制，`smart` 为 0/1；`advance`、`flush`、`reset` 使用 `-`。帧内发送端时间以纳秒保存，两套时钟在此固定轨迹中同源。操作顺序包含计时器调度，不能仅按帧时间重排。

每个场景以 `reset` 和 `smart=1` 开始，整个文件以 `reset` 结束，允许反复回放。协议黄金样例仍位于 `protocol/fixtures/`；本目录补充有状态动作序列。

执行 `bash tools/RustCoreComparison/run.sh` 可逐步核对 Swift 与 Rust 的动作和下一次计时截止时间。随机压力轨迹使用固定种子，每次生成相同的输入。
