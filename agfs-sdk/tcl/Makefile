# AGFS Tcl SDK Makefile

.PHONY: all test demo shell install clean help

# 默认目标
all: test

# 运行基本测试
test:
	@echo "运行AGFS Tcl SDK测试..."
	@tclsh test_basic.tcl

# 运行简单演示
demo:
	@echo "运行简单演示..."
	@tclsh examples/demo.tcl

# 启动交互式shell
shell:
	@echo "启动AGFS Tcl Shell..."
	@tclsh shell_example.tcl

# 运行所有示例
examples:
	@echo "运行基本示例..."
	@tclsh examples/basic_usage.tcl
	@echo ""
	@echo "运行高级示例..."
	@tclsh examples/advanced_usage.tcl

# 安装SDK
install:
	@./install.sh

# 清理临时文件
clean:
	@find . -name "*.tmp" -delete 2>/dev/null || true
	@find /tmp -name "agfs_test_*" -delete 2>/dev/null || true
	@find /tmp -name "tcl_test_*" -delete 2>/dev/null || true
	@find /tmp -name "downloaded_*" -delete 2>/dev/null || true
	@echo "清理完成"

# 验证SDK
verify:
	@echo "验证SDK安装..."
	@tclsh <<'EOF'
set auto_path [linsert $auto_path 0 [file dirname [file normalize [info script]]]]
puts "检查包..."
if {[catch { package require agfs } err]} {
    puts "✗ 无法加载agfs包: $err"
    exit 1
}
puts "✓ agfs包已加载"

puts "检查版本..."
puts "✓ SDK版本: [agfs::version]"

puts "检查依赖..."
set deps {http uri json}
foreach dep $deps {
    if {[catch { package require $dep } err]} {
        puts "✗ 缺少依赖: $dep"
    } else {
        puts "✓ $dep 已加载"
    }
}
puts ""
puts "验证完成！"
EOF

# 显示帮助
help:
	@echo "AGFS Tcl SDK Makefile"
	@echo ""
	@echo "可用目标:"
	@echo "  all      - 运行测试（默认）"
	@echo "  test     - 运行基本测试"
	@echo "  demo     - 运行简单演示"
	@echo "  shell    - 启动交互式shell"
	@echo "  examples - 运行所有示例"
	@echo "  install  - 安装SDK"
	@echo "  verify   - 验证SDK安装"
	@echo "  clean    - 清理临时文件"
	@echo "  help     - 显示此帮助"
	@echo ""
	@echo "示例:"
	@echo "  make test      # 运行测试"
	@echo "  make demo      # 运行演示"
	@echo "  make shell     # 启动shell"
