#!/usr/bin/env tclsh
# 简单演示脚本 - 展示Tcl SDK的基本用法

set auto_path [linsert $auto_path 0 [file dirname [file dirname [file normalize [info script]]]]]

package require agfs

proc ::normalize_demo_base {value} {
    # Determine which mount the demo should use (defaults to /memfs)
    set base $value
    if {$base eq ""} {
        set base "/memfs"
    }
    if {[string index $base 0] ne "/"} {
        set base "/$base"
    }
    return [string trimright $base "/"]
}

set demo_base_env ""
if {[info exists ::env(AGFS_DEMO_BASE)]} {
    set demo_base_env $::env(AGFS_DEMO_BASE)
}
set preferred_base [::normalize_demo_base $demo_base_env]
set demo_base ""

puts "\n========================================"
puts "  AGFS Tcl SDK 简单演示"
puts "========================================\n"

# 配置
puts "1. 初始化客户端..."
set client [agfs::AGFSClient -api_base "http://localhost:8080"]
puts "   ✓ 客户端已创建"
puts "   首选挂载前缀: $preferred_base (可通过环境变量 AGFS_DEMO_BASE 覆盖)"

# 测试连接
puts "\n2. 测试服务器连接..."
if {[catch {
    set health [$client health]
    puts "   ✓ 服务器连接成功"
    puts "   版本: [dict get $health version]"
} err]} {
    puts "   ✗ 连接失败: $err"
    puts "   请确保AGFS服务器正在运行"
    exit 1
}

# 简单操作
puts "\n3. 执行基本操作..."

# 构建挂载候选列表（首选 -> 常用 -> 根目录列出的挂载）
set mount_candidates {}
if {$preferred_base ne ""} {
    lappend mount_candidates $preferred_base
}
foreach fallback {/memfs /local/tmp /local /tmp /} {
    if {[lsearch -exact $mount_candidates $fallback] < 0} {
        lappend mount_candidates $fallback
    }
}
if {![catch {set root_entries [$client ls "/"]} root_err]} {
    foreach entry $root_entries {
        if {[dict exists $entry name]} {
            set candidate "/[dict get $entry name]"
            if {[lsearch -exact $mount_candidates $candidate] < 0} {
                lappend mount_candidates $candidate
            }
        }
    }
} else {
    puts "   - 无法列出根目录以发现挂载点: $root_err"
}

# 选择可写挂载并确保演示目录存在
set test_dir ""
set dir_status ""
set last_error ""
foreach base $mount_candidates {
    set candidate [string trimright $base "/"]
    if {$candidate eq ""} {
        continue
    }
    set potential_dir "$candidate/tcl_demo"
    if {![catch {$client mkdir $potential_dir} errMsg]} {
        set demo_base $candidate
        set test_dir $potential_dir
        set dir_status created
        break
    }
    if {[string match -nocase "*already exists*" $errMsg]} {
        set demo_base $candidate
        set test_dir $potential_dir
        set dir_status exists
        break
    }
    if {[string match -nocase "*not found*" $errMsg]} {
        continue
    }
    set last_error $errMsg
}

if {$test_dir eq ""} {
    puts "   ✗ 无法找到可写的挂载点。尝试路径: [join $mount_candidates {, }]"
    if {$last_error ne ""} {
        puts "   最后错误: $last_error"
    }
    puts "   请将 AGFS_DEMO_BASE 设置为现有且可写的挂载点（例如 /local/tmp），或在服务器上启用 /memfs 等插件后重试。"
    exit 1
}

puts "   ✓ 使用挂载前缀: $demo_base"
if {$dir_status eq "created"} {
    puts "   ✓ 创建目录: $test_dir"
} else {
    puts "   - 目录已存在: $test_dir (继续)"
}

# 写入文件
set demo_file "$test_dir/demo.txt"
$client write $demo_file "这是Tcl SDK的演示文件\n创建时间: [clock format [clock seconds]]"
puts "   ✓ 写入文件: $demo_file"

# 读取文件
set content [$client cat $demo_file]
puts "   ✓ 读取文件内容:"
puts "   ----------------"
foreach line [split $content "\n"] {
    if {$line != ""} {
        puts "   $line"
    }
}
puts "   ----------------"

# 列出目录
puts "\n4. 列出目录内容..."
set files [$client ls $test_dir]
puts "   目录 '$test_dir' 包含:"
foreach file $files {
    set name [dict get $file name]
    set size [dict get $file size]
    puts "     - $name ($size 字节)"
}

# 演示辅助函数
puts "\n5. 演示辅助函数..."

# 上传本地文件
set local_file "/tmp/tcl_test_$$.txt"
set fp [open $local_file w]
puts $fp "本地测试文件\n用于演示上传功能"
close $fp

set remote_uploaded "$test_dir/uploaded.txt"
agfs::upload $client $local_file $remote_uploaded
puts "   ✓ 上传: $local_file -> $remote_uploaded"

# 下载文件
set downloaded "/tmp/downloaded_$$.txt"
agfs::download $client $remote_uploaded $downloaded
puts "   ✓ 下载: $remote_uploaded -> $downloaded"

# 复制文件
set copied "$test_dir/copied.txt"
agfs::cp $client $demo_file $copied
puts "   ✓ 复制: $demo_file -> $copied"

# 清理
puts "\n6. 清理测试数据..."
catch { $client rm $test_dir -recursive true }
catch { file delete $local_file }
catch { file delete $downloaded }
puts "   ✓ 清理完成"

puts "\n========================================"
puts "  演示完成！"
puts "========================================\n"
puts "提示："
puts "  - 运行 'tclsh shell_example.tcl' 启动交互式shell"
puts "  - 运行 'tclsh test_basic.tcl' 运行完整测试"
puts "  - 查看 'examples/' 目录获取更多示例\n"
