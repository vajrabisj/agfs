# AGFS Tcl SDK 快速开始

## 概述

Tcl语言的AGFS（聚合文件系统）客户端SDK，允许你通过Tcl脚本与AGFS服务器连接和通信。

## 安装要求

- Tcl 9.0+
- 系统已安装tcllib（通过Homebrew的tcl-tk安装）
- AGFS服务器运行中

## 快速使用

### 1. 基本脚本

```tcl
#!/usr/bin/env tclsh
# 设置SDK路径
set auto_path [linsert $auto_path 0 "/Users/vajra/Clang/agfs/agfs-sdk/tcl"]
set auto_path [linsert $auto_path 0 /opt/homebrew/Cellar/tcl-tk/9.0.2/lib/tcllib2.0]

# 加载AGFS包
package require agfs

# 创建客户端
set client [agfs::AGFSClient -api_base "http://localhost:8080"]

# 使用客户端
set health [$client health]
puts "服务器版本: [dict get $health version]"

# 列出目录
set files [$client ls /]
foreach file $files {
    puts "[dict get $file name]"
}

# 写入文件
$client write "/test.txt" "Hello from Tcl!"

# 读取文件
set content [$client cat "/test.txt"]
puts $content
```

### 2. 运行示例

```bash
# 简单演示
cd /Users/vajra/Clang/agfs/agfs-sdk/tcl
tclsh examples/demo.tcl

# 交互式Shell
tclsh shell_example.tcl

# 完整测试
tclsh test_basic.tcl
```

### 3. 主要功能

#### 文件操作
```tcl
# 读取文件
set data [$client cat "/path/to/file.txt"]

# 写入文件
$client write "/path/to/file.txt" "内容"

# 创建目录
$client mkdir "/new/directory"

# 删除文件
$client rm "/path/to/file.txt"

# 递归删除目录
$client rm "/path/to/directory" -recursive true

# 重命名/移动
$client mv "/old/path.txt" "/new/path.txt"
```

#### 文件传输
```tcl
# 上传本地文件到AGFS
agfs::upload $client "/local/file.txt" "/remote/file.txt"

# 下载AGFS文件到本地
agfs::download $client "/remote/file.txt" "/local/file.txt"

# 复制AGFS内的文件
agfs::cp $client "/source/file.txt" "/dest/file.txt"

# 递归传输目录
agfs::upload $client "/local/dir" "/remote/dir" -recursive true
agfs::download $client "/remote/dir" "/local/dir" -recursive true
agfs::cp $client "/source/dir" "/dest/dir" -recursive true
```

#### 搜索和校验
```tcl
# 搜索文件内容
set results [$client grep "/path/to/search" "pattern" -recursive true]

# 计算文件校验和
set digest [$client digest "/path/to/file.txt" "md5"]
puts [dict get $digest digest]
```

### 4. 交互式Shell

运行交互式shell：
```bash
tclsh shell_example.tcl
```

支持的命令：
- `help` - 显示帮助
- `ls [path]` - 列出目录
- `cat <file>` - 查看文件
- `mkdir <dir>` - 创建目录
- `upload <local> <remote>` - 上传文件
- `download <remote> <local>` - 下载文件
- `exit` - 退出shell

### 5. 错误处理

```tcl
if {[catch {
    $client cat "/nonexistent.txt"
} err]} {
    puts "错误: $err"
    # 处理错误...
}
```

## 文件结构

```
agfs-sdk/tcl/
├── agfs.tcl              # 主包文件
├── agfsclient.tcl        # 核心客户端
├── exceptions.tcl        # 异常处理
├── helpers.tcl           # 帮助函数
├── pkgIndex.tcl          # 包索引
├── README.md             # 完整文档
├── QUICKSTART.md         # 本文件
├── Makefile              # 构建脚本
├── install.sh            # 安装脚本
├── test_basic.tcl        # 基本测试
├── shell_example.tcl     # 交互式Shell
└── examples/
    ├── demo.tcl          # 简单演示
    ├── basic_usage.tcl   # 基本用法
    └── advanced_usage.tcl # 高级用法
```

## 常用命令

```bash
# 验证SDK安装
cd /Users/vajra/Clang/agfs/agfs-sdk/tcl
make verify

# 运行测试
make test

# 运行演示
make demo

# 启动shell
make shell
```

## 连接远程服务器

```tcl
# 连接远程AGFS服务器
set client [agfs::AGFSClient \
    -api_base "http://192.168.1.100:8080" \
    -timeout 30]
```

## 故障排除

### 问题1: 找不到agfs包
```
can't find package agfs
```
**解决**: 确保auto_path包含SDK目录：
```tcl
set auto_path [linsert $auto_path 0 "/Users/vajra/Clang/agfs/agfs-sdk/tcl"]
```

### 问题2: 找不到json包
```
can't find package json
```
**解决**: 确保安装了tcllib：
```bash
brew install tcllib
# 或者使用已安装的tcl-tk中的tcllib
set auto_path [linsert $auto_path 0 /opt/homebrew/Cellar/tcl-tk/9.0.2/lib/tcllib2.0]
```

### 问题3: 连接被拒绝
```
Connection refused
```
**解决**: 确保AGFS服务器正在运行：
```bash
docker run -p 8080:8080 c4pt0r/agfs-server:latest
```

## 下一步

- 查看 `README.md` 获取完整API文档
- 运行 `examples/` 中的示例脚本
- 使用交互式shell体验功能
- 开始编写你的Tcl脚本！

## 示例脚本

查看以下示例：
- `examples/demo.tcl` - 5分钟快速入门
- `examples/basic_usage.tcl` - 基础功能展示
- `examples/advanced_usage.tcl` - 高级功能演示
- `shell_example.tcl` - 交互式命令行工具

---

**AGFS Tcl SDK** - 让Tcl脚本也能轻松使用分布式文件系统！
