# Rust 共享核心原型

此模块用 Rust 实现 protocol v1 codec、增量流解码和与现有 Swift 默认配置对应的纯手势状态机。零第三方依赖，Cargo 声明最低 Rust 1.83，当前验证使用 Rust 1.95。它只产出动作，没有网络、UI 或平台输入注入。

`src/model.rs` 定义领域帧与固定容量动作；`protocol.rs` 校验线格式；`gesture.rs` 维护会话与计时；`ffi.rs` 导出 C ABI；`traces.rs` 与 `core-replay` 回放共享输入并测量原生路径。

```sh
cargo test --manifest-path core-rust/Cargo.toml --locked --offline
cargo build --manifest-path core-rust/Cargo.toml --release --locked --offline
core-rust/target/release/core-replay protocol/trajectories/gestures-v1.trace 64 51
bash tools/RustCoreComparison/run.sh
```

C 接口见 `include/motouchpad_core.h`。Swift 调用者借用完整网络帧的字节缓冲，Rust 在栈上解码并写入调用者预分配的八动作缓冲。句柄由 create/destroy 成对管理，同一句柄不能并发调用，缓冲必须有效、对齐且不与句柄重叠。下一次计时截止时间由调用者读取并调度；取消/断连时必须执行 reset 并消费释放动作。

原型支持现有全部 15 个命名命令，遵从 Swift 默认阈值，并允许切换智能缩放。Swift 的其他自定义 Config 参数尚未导出。C ABI 不暴露 Rust 枚举或容器布局。参数/协议错误保留原状态；捕获内部 panic 后重置并返回 -3，调用者应主动释放已注入的按键。内存不足与无效指针不属于可恢复错误。

原生模型 API 要求最多五个合法联系人；跨语言入口先校验协议再推进状态。编码器输出规范化字节：灵敏度别名 0 编码为 100。增量解码器用于分片/合帧测试，当前 C ABI 接收完整单帧。

原型用于评估共享实现和调用成本。桌面应用当前使用各自的原生核心；迁移判断与实测数据见 [评估报告](../docs/rust-core-evaluation.md)。
