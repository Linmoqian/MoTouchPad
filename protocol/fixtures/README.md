# Protocol v1 fixtures

每个 hex 文件是一帧协议 v1 的完整字节序列，使用空白分隔的十六进制字节。
文件名和清单由 manifest.json 管理。stream-two-frames.hex 是两帧无分隔符
拼接后的 TCP 字节流，用来验证分片接收和多帧合并。

编码器输出应与对应的黄金字节一致；解码器必须拒绝 invalid-*.hex。
浮点数字段按 IEEE-754 binary32 little-endian 编码。
