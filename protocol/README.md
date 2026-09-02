# MoTouchPad 协议目录

这里是 MoTouchPad v1 网络协议的唯一线协议源。

- [PROTOCOL.md](PROTOCOL.md)：字段布局、合法值和发送语义。
- [fixtures/](fixtures/)：跨语言共享的黄金字节样例。hex 文件使用空白分隔的十六进制字节。

各端可以保留自己的原生模型，但只能通过本端 encode(TouchFrame) /
decode(bytes) codec 进入网络层。协议目录不包含驱动 IOCTL；驱动协议属于
windows-driver/ 和 mac-driver/ 的独立实验边界。

本地检查：

    python3 tools/validate_protocol_fixtures.py
