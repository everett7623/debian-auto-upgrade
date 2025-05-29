#!/bin/bash

# 升级选择功能演示脚本
# 展示重启后不同选择的效果

echo "🎯 Debian 升级选择功能演示"
echo "=================================="
echo

echo "📋 重启后升级选择说明："
echo
echo "当 Debian 系统升级并重启后，脚本会检测升级状态并提供以下选择："
echo

echo "┌─────────────────────────────────────────────────────────────────┐"
echo "│  选项  │  说明                    │  状态文件  │  下次重启       │"
echo "├─────────────────────────────────────────────────────────────────┤"
echo "│  [Y]   │  立即继续升级             │  清除      │  如有升级会询问  │"
echo "│  [N]   │  永久保持当前版本         │  清除      │  不再提示升级    │"
echo "│  [S]   │  暂时跳过，稍后升级       │  保留      │  继续询问升级    │"
echo "│  [C]   │  检查系统状态             │  保留      │  继续询问升级    │"
echo "│  [Q]   │  退出脚本                │  保留      │  继续询问升级    │"
echo "└─────────────────────────────────────────────────────────────────┘"
echo

echo "💡 使用场景举例："
echo

echo "🔹 场景1：生产服务器逐步升级"
echo "   Debian 10 → 11 (重启) → 选择[S]暂时跳过"
echo "   → 运维窗口时再次运行脚本 → 选择[Y]继续升级到12"
echo

echo "🔹 场景2：保持稳定版本"
echo "   Debian 11 → 12 (重启) → 选择[N]永久保持"
echo "   → 以后重启都不会再提示升级到测试版本"
echo

echo "🔹 场景3：测试环境持续升级"
echo "   每次重启后选择[Y]，持续升级到最新版本"
echo

echo "🔹 场景4：暂时不确定"
echo "   选择[Q]退出或[C]检查，保留升级状态"
echo "   → 稍后可以重新运行脚本做决定"
echo

echo "⚠️  重要提醒："
echo "• 只有选择[N]才会永久停止升级提示"
echo "• 选择[S]会保留状态，多次跳过会有温馨提醒"
echo "• 升级状态文件保存在 /var/lib/debian_upgrade_state"
echo "• 备份文件保存在 /etc/debian_upgrade_state.backup"
echo

echo "🧪 测试命令："
echo "# 手动创建升级状态进行测试"
echo "sudo mkdir -p /var/lib"
echo 'cat << EOF | sudo tee /var/lib/debian_upgrade_state > /dev/null'
echo "PREVIOUS_VERSION=10"
echo "CURRENT_VERSION=11" 
echo "TARGET_VERSION=11"
echo "UPGRADE_TIME=$(date '+%Y-%m-%d %H:%M:%S')"
echo "SCRIPT_VERSION=2.2"
echo "REBOOT_PENDING=1"
echo "EOF"
echo
echo "# 测试升级状态检查"
echo "./debian_upgrade.sh --check-state"
echo
echo "# 清理测试状态"
echo "sudo rm -f /var/lib/debian_upgrade_state /etc/debian_upgrade_state.backup"
echo

echo "=================================="
echo "感谢使用 Debian 自动升级工具！ 🚀"
