# Contributing

感谢参与改进。发行版升级脚本具有较高风险，提交应保持小而清晰，并说明实际验证范围。

## 开发流程

1. 从 `main` 创建功能分支。
2. 修改脚本时同步更新帮助信息、README 或安全文档。
3. 运行 `make check`。
4. 在 Pull Request 中说明测试过的 Debian 版本、启动方式和虚拟化环境。

## 代码要求

- 使用 Bash，不引入仅在某一发行版可用的非必要依赖。
- 对变量和路径加引号，临时文件使用独立目录。
- 不删除 APT/dpkg 锁文件。
- 不在默认流程中写入 MBR、重装引导器或重启网络。
- destructive 操作必须有明确确认、备份和失败处理。
- 新增版本升级前先对照 Debian 官方 Release Notes。

## 提交信息

推荐使用简洁的命令式主题，例如：

```text
fix: wait for apt locks instead of deleting them
docs: clarify third-party repository recovery
```
