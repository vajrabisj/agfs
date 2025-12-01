# AGFS Tcl SDK 安装指南 (Tcl 9.0)

## ✅ 安装完成

AGFS Tcl SDK 已成功创建并适配 Tcl 9.0！

---

## 📍 SDK 位置

```
/Users/vajra/Clang/agfs/agfs-sdk/tcl/
├── agfs.tcl                    # 主包文件
├── agfsclient.tcl              # 核心客户端
├── exceptions.tcl              # 异常处理
├── helpers.tcl                 # 帮助函数
├── pkgIndex.tcl                # 包索引
├── README.md                   # 完整文档
├── QUICKSTART.md               # 快速开始
├── verify_sdk.tcl              # 验证脚本
└── examples/                   # 示例目录
    ├── demo.tcl
    ├── basic_usage.tcl
    └── advanced_usage.tcl
```

---

## 🚀 快速使用

### 1. 验证安装

```bash
cd /Users/vajra/Clang/agfs/agfs-sdk/tcl
tclsh9.0 verify_sdk.tcl
```

### 2. 运行演示

```bash
# 简单演示
tclsh9.0 examples/demo.tcl

# 基础用法
tclsh9.0 examples/basic_usage.tcl
```

### 3. 在脚本中使用

```tcl
#!/usr/bin/env tclsh9.0
set auto_path [linsert $auto_path 0 /opt/homebrew/Cellar/tcl-tk/9.0.2/lib/tcllib2.0]
set auto_path [linsert $auto_path 0 /opt/homebrew/Cellar/tcl-tk/9.0.2/lib/tcllibc2.0]
set auto_path [linsert $auto_path 0 /Users/vajra/Clang/agfs/agfs-sdk/tcl]

package require agfs

set client [agfs::AGFSClient -api_base "http://localhost:8080"]

# 使用SDK
$client write "/hello.txt" "Hello from Tcl 9.0!"
set content [$client cat "/hello.txt"
puts $content
```

---

## 🔧 修复的问题

1. **Tcl 9.0 默认参数语法** - 所有 `proc` 定义中的默认参数已用花括号包围
2. **JSON 解析** - 修复了 http::data 返回列表的解码问题
3. **URL 编码** - 添加了自定义的 UrlEncode 函数替代缺失的 uri::encode
4. **HTTP 响应处理** - 处理了二进制编码的响应数据

---

## 📦 依赖项

- **Tcl 9.0** ✓ 已安装
- **tcllib** ✓ 系统已有 (版本 1.3.6)
- **http** ✓ 内置包
- **uri** ✓ 内置包
- **json** ✓ tcllib 包含

---

## ✅ 验证状态

- ✓ SDK 包加载正常
- ✓ 客户端创建成功
- ✓ HTTP 连接正常 (服务器运行时)
- ✓ 基本文件操作可用
- ✓ 辅助函数可用

---

## 🎯 使用建议

### 启动 AGFS 服务器

```bash
# 使用 Docker
docker run -d --name agfs-server -p 8080:8080 c4pt0r/agfs-server:latest

# 或使用本地安装
cd /path/to/agfs-server
go run main.go
```

### 运行完整测试

```bash
cd /Users/vajra/Clang/agfs/agfs-sdk/tcl
make test
```

### 在交互式 Shell 中使用

```tcl
$ tclsh9.0
% set auto_path [linsert $auto_path 0 /opt/homebrew/Cellar/tcl-tk/9.0.2/lib/tcllib2.0]
% set auto_path [linsert $auto_path 0 /opt/homebrew/Cellar/tcl-tk/9.0.2/lib/tcllibc2.0]
% set auto_path [linsert $auto_path 0 /Users/vajra/Clang/agfs/agfs-sdk/tcl]
% package require agfs
% set client [agfs::AGFSClient -api_base "http://localhost:8080"]
% $client health
% $client ls /
% exit
```

---

## 📚 文档

- **完整文档**: `README.md`
- **快速开始**: `QUICKSTART.md`
- **示例**: `examples/` 目录

---

## 🎉 完成！

AGFS Tcl SDK 已经完全适配 Tcl 9.0，可以正常使用了！

**启动你的 AGFS 服务器，然后开始使用 SDK 吧！** 🚀

---

## 💡 提示

1. **设置环境变量** (可选):
   ```bash
   export TCLLIBPATH="/opt/homebrew/Cellar/tcl-tk/9.0.2/lib/tcllib2.0:$TCLLIBPATH"
   ```

2. **创建符号链接** (可选):
   ```bash
   ln -s /Users/vajra/Clang/agfs/agfs-sdk/tcl /usr/local/lib/agfs-tcl
   export TCLLIBPATH="/usr/local/lib/agfs-tcl:$TCLLIBPATH"
   ```

3. **查看更多示例**:
   ```bash
   tclsh9.0 examples/advanced_usage.tcl
   ```
