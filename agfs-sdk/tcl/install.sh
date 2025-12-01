#!/bin/bash
# AGFS Tcl SDK 安装脚本

echo "========================================="
echo "  AGFS Tcl SDK 安装程序"
echo "========================================="
echo ""

# 检查Tcl
echo "检查Tcl版本..."
if ! command -v tclsh &> /dev/null; then
    echo "错误: 未找到tclsh命令"
    echo "请安装Tcl 9.0或更高版本"
    exit 1
fi

TCL_VERSION=$(tclsh <<< 'puts [info tclversion]')
echo "发现Tcl版本: $TCL_VERSION"

# 检查必要的包
echo ""
echo "检查Tcl包..."
PACKAGES_OK=true

# 检查http包
if ! tclsh <<< 'package require http' 2>/dev/null; then
    echo "警告: http包未找到（通常内置在Tcl中）"
    PACKAGES_OK=false
fi

# 检查json包
if ! tclsh <<< 'package require json' 2>/dev/null; then
    echo "警告: json包未找到"
    echo "  请安装tcllib: brew install tcllib"
    PACKAGES_OK=false
fi

# 检查uri包
if ! tclsh <<< 'package require uri' 2>/dev/null; then
    echo "警告: uri包未找到（通常内置在Tcl中）"
    PACKAGES_OK=false
fi

if [ "$PACKAGES_OK" = false ]; then
    echo ""
    echo "某些包缺失，可能影响功能。"
    echo "建议安装缺失的包。"
fi

# 设置路径
echo ""
echo "设置安装路径..."
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
TCL_SDK_DIR="$SCRIPT_DIR"

echo "SDK位置: $TCL_SDK_DIR"

# 创建符号链接（可选）
echo ""
echo "是否要创建全局符号链接？(需要sudo权限)"
read -p "创建符号链接 /usr/local/lib/agfs-tcl ? (y/N): " CREATE_LINK

if [[ $CREATE_LINK =~ ^[Yy]$ ]]; then
    if sudo mkdir -p /usr/local/lib 2>/dev/null; then
        sudo ln -sfn "$TCL_SDK_DIR" /usr/local/lib/agfs-tcl

        # 添加到TCLLIBPATH
        if ! grep -q "/usr/local/lib/agfs-tcl" ~/.bashrc 2>/dev/null; then
            echo "" >> ~/.bashrc
            echo "# AGFS Tcl SDK" >> ~/.bashrc
            echo "export TCLLIBPATH=\"/usr/local/lib/agfs-tcl:\$TCLLIBPATH\"" >> ~/.bashrc
            echo "已添加到 ~/.bashrc"
        fi

        echo "✓ 符号链接创建完成"
        echo "✓ 请运行 'source ~/.bashrc' 或重新打开终端"
    else
        echo "无法创建符号链接（权限不足）"
    fi
fi

# 创建示例脚本快捷方式
echo ""
echo "创建示例脚本快捷方式..."
cat > /tmp/agfs-tcl-run <<'EOF'
#!/bin/bash
# AGFS Tcl SDK 运行器
TCL_SDK_DIR="$(dirname "$(dirname "$(dirname "$(readlink -f "$0")")")")"
tclsh "$TCL_SDK_DIR/shell_example.tcl" "$@"
EOF

chmod +x /tmp/agfs-tcl-run
sudo mv /tmp/agfs-tcl-run /usr/local/bin/agfs-tcl 2>/dev/null || mv /tmp/agfs-tcl-run ~/agfs-tcl 2>/dev/null

if [ -f /usr/local/bin/agfs-tcl ]; then
    echo "✓ 创建了 'agfs-tcl' 命令"
elif [ -f ~/agfs-tcl ]; then
    echo "✓ 创建了 '~/agfs-tcl' 脚本"
fi

# 测试安装
echo ""
echo "测试安装..."
tclsh <<'EOF'
set auto_path [linsert $auto_path 0 [file dirname [file normalize [info script]]]]
if {[catch {
    package require agfs
    puts "✓ SDK加载成功"
    puts "版本: [agfs::version]"
} err]} {
    puts "✗ SDK加载失败: $err"
    exit 1
}
EOF

if [ $? -eq 0 ]; then
    echo ""
    echo "========================================="
    echo "  安装完成！"
    echo "========================================="
    echo ""
    echo "使用方法:"
    echo "  1. 在脚本中添加:"
    echo "     set auto_path [linsert \$auto_path 0 \"$TCL_SDK_DIR\"]"
    echo "     package require agfs"
    echo ""
    echo "  2. 或设置环境变量:"
    echo "     export TCLLIBPATH=\"$TCL_SDK_DIR:\$TCLLIBPATH\""
    echo ""
    echo "  3. 运行示例:"
    echo "     tclsh $TCL_SDK_DIR/examples/demo.tcl"
    echo "     tclsh $TCL_SDK_DIR/shell_example.tcl"
    echo ""
    echo "  4. 运行测试:"
    echo "     tclsh $TCL_SDK_DIR/test_basic.tcl"
    echo ""
else
    echo ""
    echo "安装可能有问题，请检查错误信息。"
fi
