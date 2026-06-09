# Development Guide

## 环境

推荐在 Debian 12 或 13 虚拟机中开发：

```bash
sudo apt-get install bash shellcheck make git
make check
```

Windows 可使用 Git Bash 进行语法检查，但完整行为测试必须在隔离的 Debian 虚拟机中完成。

## 项目结构

- `debian_upgrade.sh`：当前支持的统一入口。
- `scripts/`：历史分版本脚本，仅供参考。
- `tests/smoke.sh`：无特权冒烟测试。
- `docs/SAFETY.md`：高风险操作约束。

## 测试层级

1. `bash -n`：全部脚本语法检查。
2. `shellcheck`：静态分析。
3. `tests/smoke.sh`：帮助、版本映射和默认策略。
4. 虚拟机快照测试：APT 源切换、失败恢复、重启和服务验证。

不要在开发机或唯一生产实例上测试发行版升级。

## 发布前检查

- 更新 `SCRIPT_VERSION`、`SCRIPT_DATE` 和 `CHANGELOG.md`。
- 核对 README 中的支持矩阵。
- 在 BIOS 与 UEFI 虚拟机中分别测试。
- 至少验证官方源和一个镜像源。
- 验证失败路径不会删除锁、修改网卡名或写入错误磁盘。
