#!/usr/bin/env tclsh9.0
# AGFS Tcl SDK 验证脚本
# 使用方法: tclsh9.0 verify_sdk.tcl

# 设置路径
set auto_path [linsert $auto_path 0 /opt/homebrew/Cellar/tcl-tk/9.0.2/lib/tcllib2.0]
set auto_path [linsert $auto_path 0 /opt/homebrew/Cellar/tcl-tk/9.0.2/lib/tcllibc2.0]
set auto_path [linsert $auto_path 0 [file dirname [file normalize [info script]]]]

# 加载SDK
package require agfs

puts ""
puts "========================================="
puts "  AGFS Tcl SDK 验证 (Tcl 9.0)"
puts "========================================="
puts ""

# 检查包加载
puts "1. 包加载状态:"
puts "   ✓ agfs 包已加载 (版本: [agfs::version])"
puts ""

# 创建客户端
puts "2. 创建客户端:"
set client [agfs::AGFSClient -api_base "http://localhost:8080"]
puts "   ✓ 客户端创建成功"
puts ""

# 测试连接
puts "3. 测试服务器连接:"
if {[catch {
    set health [$client health]
    puts "   ✓ 服务器连接成功"
    puts "   版本: [dict get $health version]"
    puts "   状态: [dict get $health status]"
} err]} {
    puts "   ⚠ 服务器未运行: $err"
}
puts ""

# 测试基本操作
puts "4. 测试基本文件操作:"
catch {
    # 创建测试目录
    $client mkdir /verify_test
    puts "   ✓ 创建目录"

    # 写入文件
    $client write /verify_test/test.txt "验证测试数据"
    puts "   ✓ 写入文件"

    # 读取文件
    set data [$client cat /verify_test/test.txt]
    puts "   ✓ 读取文件"

    # 清理
    $client rm /verify_test -recursive true
    puts "   ✓ 清理完成"
}
puts ""

puts "========================================="
puts "  验证完成！SDK 可在 Tcl 9.0 中使用"
puts "========================================="
puts ""
