# AGFS Tcl SDK

Tcl客户端库，用于与AGFS（聚合文件系统）服务器进行交互。

## 功能特性

- ✅ 文件系统操作（读取、写入、创建、删除）
- ✅ 目录操作（列表、创建、删除）
- ✅ 文件移动和重命名
- ✅ 文件权限管理
- ✅ 插件管理（挂载、卸载、列出）
- ✅ 文件搜索（grep）
- ✅ 文件校验和计算
- ✅ 帮助函数（复制、上传、下载）
- ✅ 错误处理和异常
- ✅ 支持流式操作（大文件处理）
- ✅ 交互式shell

## 先决条件

- Tcl 9.0 或更高版本
- AGFS 服务器运行在 localhost:8080 或其他地址
- 必需的Tcl包：
  - `http` (内置)
  - `uri` (内置)
  - `json` (tcllib)

## 安装

1. 克隆或下载AGFS Tcl SDK
2. 确保Tcl可以找到包目录：

```bash
export TCLLIBPATH="/path/to/agfs-sdk/tcl:$TCLLIBPATH"
```

或者在Tcl脚本中设置：

```tcl
set auto_path [linsert $auto_path 0 "/path/to/agfs-sdk/tcl"]
```

## 快速开始

### 基本用法

```tcl
#!/usr/bin/env tclsh
set auto_path [linsert $auto_path 0 [file dirname [file normalize [info script]]]]

package require agfs

# 创建客户端
set client [agfs::AGFSClient -api_base "http://localhost:8080"]

# 检查服务器健康状态
set health [$client health]
puts "Server version: [dict get $health version]"

# 列出目录
set files [$client ls /]
foreach file $files {
    puts "[dict get $file name]"
}

# 创建目录
$client mkdir /my_project

# 写入文件
$client write "/my_project/readme.txt" "Hello from AGFS Tcl SDK!"

# 读取文件
set content [$client cat "/my_project/readme.txt"]
puts $content
```

### 文件操作

```tcl
# 写入文件
$client write "/path/to/file.txt" "File content"

# 读取文件
set data [$client cat "/path/to/file.txt"]

# 获取文件信息
set info [$client stat "/path/to/file.txt"]
puts "Size: [dict get $info size] bytes"

# 重命名/移动文件
$client mv "/old/path.txt" "/new/path.txt"

# 删除文件
$client rm "/path/to/file.txt"

# 删除目录（递归）
$client rm "/path/to/directory" -recursive true
```

### 目录操作

```tcl
# 创建目录
$client mkdir "/new/directory"

# 列出目录内容
set files [$client ls "/some/directory"]
foreach file $files {
    set type [expr {[dict get $file isDir] ? "DIR" : "FILE"}]
    puts "[dict get $file name] ($type)"
}

# 更改文件权限
$client chmod "/path/to/file" 755
```

### 辅助函数

```tcl
# 在AGFS内复制文件
agfs::cp $client "/source/file.txt" "/destination/file.txt"

# 递归复制目录
agfs::cp $client "/source/dir" "/dest/dir" -recursive true

# 从本地上传到AGFS
agfs::upload $client "/local/file.txt" "/remote/file.txt"

# 递归上传目录
agfs::upload $client "/local/directory" "/remote/directory" -recursive true

# 从AGFS下载到本地
agfs::download $client "/remote/file.txt" "/local/file.txt"

# 递归下载目录
agfs::download $client "/remote/directory" "/local/directory" -recursive true

# 流式传输大文件
agfs::upload $client "/huge/file.dat" "/remote/file.dat" -stream true
agfs::download $client "/remote/huge.dat" "/local/huge.dat" -stream true
```

### 插件管理

```tcl
# 列出挂载的文件系统
set mounts [$client mounts]
foreach mount $mounts {
    puts "[dict get $mount name] at [dict get $mount path]"
}

# 挂载新插件
set config [dict create bucket "my-bucket" region "us-west-2"]
$client mount "s3fs" "/s3-backup" $config

# 卸载插件
$client unmount "/s3-backup"

# 加载外部插件
$client load_plugin "/path/to/custom_plugin.so"

# 列出已加载的插件
set plugins [$client list_plugins]
puts "Loaded: $plugins"
```

### 搜索和校验和

```tcl
# 搜索文件中的模式
set results [$client grep "/path/to/search" "pattern" -recursive true -case_insensitive false]
foreach result $results {
    puts "[dict get $result file]:[dict get $result line] - [dict get $result content]"
}

# 计算文件校验和
set digest [$client digest "/path/to/file.txt" "md5"]
puts "MD5: [dict get $digest digest]"
```

### 错误处理

```tcl
# 捕获和处理错误
if {[catch {
    $client cat "/nonexistent.txt"
} err]} {
    puts "Error: $err"
    # 处理错误...
}
```

## 示例

SDK包含几个示例脚本：

1. **基本用法** (`examples/basic_usage.tcl`)
   - 基本文件操作
   - 目录管理
   - 上传/下载

2. **高级用法** (`examples/advanced_usage.tcl`)
   - 批量文件处理
   - 错误处理
   - 目录树操作
   - 流式传输

3. **交互式Shell** (`shell_example.tcl`)
   - 类似于bash的交互式shell
   - 支持常用命令

4. **测试脚本** (`test_basic.tcl`)
   - 全面的功能测试
   - 用于验证SDK工作

5. **Agent任务循环** (`examples/agent_task_loop.tcl`)
   - 基于QueueFS的任务分发
   - 模拟Python `task_loop` 的工作流
   - 支持调用本地Ollama模型（默认 `qwen3:4b`，超时时间2分钟）
   - 可处理带多步骤的任务，并把结果写回AGFS供其它组件读取

6. **任务广播脚本** (`examples/broadcast_tasks.tcl`)
   - 将同一个任务描述同时投递到多个Agent队列
   - 自动生成任务ID及结果目录提示，便于下游Agent读取

## 客户端配置

```tcl
# 默认配置
set client [agfs::AGFSClient]

# 自定义API URL和超时
set client [agfs::AGFSClient \
    -api_base "http://192.168.1.100:8080" \
    -timeout 30]
```

## API 参考

### AGFSClient

主客户端类，用于与AGFS服务器交互。

#### 构造函数
```tcl
agfs::AGFSClient ?-api_base url? ?-timeout seconds?
```

#### 方法

**文件系统操作**
- `$client ls path` - 列出目录内容
- `$client cat path ?offset? ?size?` - 读取文件
- `$client write path data` - 写入文件
- `$client create path` - 创建空文件
- `$client mkdir path ?mode?` - 创建目录
- `$client rm path ?-recursive?` - 删除文件或目录
- `$client mv old_path new_path` - 重命名/移动
- `$client chmod path mode` - 更改权限
- `$client touch path` - 创建空文件或更新戳
- `$client stat path` - 获取文件信息

**插件管理**
- `$client mounts` - 列出挂载的文件系统
- `$client mount fstype path config` - 挂载插件
- `$client unmount path` - 卸载插件
- `$client list_plugins` - 列出已加载的插件
- `$client load_plugin library_path` - 加载外部插件
- `$client unload_plugin library_path` - 卸载插件

**其他**
- `$client health` - 检查服务器健康状态
- `$client grep path pattern ?-recursive? ?-case_insensitive?` - 搜索文件
- `$client digest path ?algorithm?` - 计算校验和

### 辅助函数

**文件传输**
- `agfs::cp client src dst ?-recursive? ?-stream?` - 复制文件
- `agfs::upload client local_path remote_path ?-recursive? ?-stream?` - 上传文件
- `agfs::download client remote_path local_path ?-recursive? ?-stream?` - 下载文件

## 运行示例

```bash
# 基本示例
tclsh examples/basic_usage.tcl

# 高级示例
tclsh examples/advanced_usage.tcl

# 交互式Shell
tclsh shell_example.tcl

# Agent循环示例
tclsh examples/agent_task_loop.tcl \
    -queue /queuefs/agent_tcl \
    -results /local/agent_results \
    -model qwen3:4b \
    -ollama_url http://localhost:11434 \
    -ollama_timeout 120000

# 任务广播示例
tclsh examples/broadcast_tasks.tcl \
    -agents agent1,agent2,agent3 \
    -task_file ./prompts/research.txt \
    -results_root /local/pipeline
```

## 多步骤Agent任务

`examples/agent_task_loop.tcl` 会监听 QueueFS，并将每个任务写回 `/local/.../agent-name/task-id.json`。任务负载支持以下字段：

```json
{
  "task": "research",
  "text": "Analyze why Tcl agents are helpful",
  "steps": [
    {"id": "outline", "prompt": "List the angles you will cover."},
    {"id": "draft", "prompt": "Write the final summary using the outline."}
  ]
}
```

- 如果 `steps` 为空，则把 `prompt`（或 `text`）直接发送给本地 Ollama 模型（默认 `qwen3:4b`）。
- 如果包含多步骤，Agent 会按顺序把 `steps` 中的 `prompt` 发送给 Ollama，并把每一步的输出记录在结果 JSON 的 `steps` 数组里。
- 所有 Ollama 请求默认 120 秒超时，可通过 `-ollama_timeout` 修改。

## 广播任务给多个 Agent

`examples/broadcast_tasks.tcl` 可将同一个任务描述一次性投递到多个 QueueFS 队列：

```bash
tclsh examples/broadcast_tasks.tcl \
    -agents agent1,agent2,agent3 \
    -queue_prefix /queuefs/agent \
    -task "Research recent progress on Tcl agents" \
    -results_root /local/pipeline
```

脚本会：
1. 为每个 Agent 创建（若不存在）对应的 `/queuefs/<agent>` 目录；
2. 生成统一的父任务 ID (`task-...`) 以及每个 Agent 的结果目录（例如 `/local/pipeline/<root_task>/<agent>`）；
3. 写入 JSON payload 到各自的 `enqueue`，payload 包含 `task_id`、`parent_task`、`description`、`result_dir` 等信息。

下游 Agent 只需继续轮询自己的 QueueFS 队列，就能接力处理这些任务。

### 多Agent流水线示例

1. **广播任务**
   ```bash
   cd agfs-sdk/tcl
   tclsh examples/broadcast_tasks.tcl \
       -agents agent1,agent2 \
       -queue_prefix /queuefs/agent \
       -task "Research recent progress on Tcl agents" \
       -results_root /local/pipeline
   ```

2. **启动Agent循环**（分别监听 `/queuefs/agent1`、`/queuefs/agent2`）
   ```bash
   tclsh examples/agent_task_loop.tcl \
       -name agent1 \
       -queue /queuefs/agent1 \
       -results /local/pipeline \
       -model qwen3:4b

   tclsh examples/agent_task_loop.tcl \
       -name agent2 \
       -queue /queuefs/agent2 \
       -results /local/pipeline \
       -model qwen3:4b
   ```
   两个 Agent 会分别把结果写到 `/local/pipeline/<root_task>/agent1`、`agent2`。

3. **（可选）汇总下一阶段**  
   当你需要再交给汇总 Agent（例如 `/queuefs/agent3`）处理时，可以手动 enqueue：
   ```bash
   cat <<'EOF' > /queuefs/agent3/enqueue
   {
     "task_id": "task-xxxx-summary",
     "parent_task": "task-xxxx",
     "description": "Combine agent1 + agent2 results into a final report.",
     "input_files": [
       "/local/pipeline/task-xxxx/agent1/web.txt",
       "/local/pipeline/task-xxxx/agent2/web.txt"
     ],
     "result_dir": "/local/pipeline/task-xxxx/final"
   }
   EOF
   ```
   然后启动第三个 `agent_task_loop.tcl` 监听 `/queuefs/agent3`，就能继续接力。

# 运行测试
tclsh test_basic.tcl
```

## 交互式Shell

SDK包含一个简单的交互式shell：

```bash
tclsh shell_example.tcl
```

支持的命令：
- `help` - 显示帮助
- `exit`, `quit` - 退出shell
- `pwd` - 打印当前目录
- `cd <dir>` - 更改目录
- `ls [dir]` - 列出目录
- `cat <file>` - 查看文件
- `echo <text>` - 回显文本
- `mkdir <dir>` - 创建目录
- `touch <file>` - 创建空文件
- `rm <path>` - 删除文件或目录
- `mv <src> <dst>` - 移动/重命名文件
- `stat <path>` - 获取文件信息
- `upload <local> <remote>` - 上传文件
- `download <remote> <local>` - 下载文件
- `cp <src> <dst>` - 复制文件

## 在脚本中使用

创建可执行的Tcl脚本：

```tcl
#!/usr/bin/env tclsh
set auto_path [linsert $auto_path 0 [file dirname [file dirname [file normalize [info script]]]]]

package require agfs

# 你的代码在这里...
```

然后使其可执行：

```bash
chmod +x your_script.tcl
./your_script.tcl
```

## 错误处理

SDK提供异常处理：

```tcl
# 基础异常
agfs::AGFSClientError "message"
agfs::AGFSConnectionError "message"
agfs::AGFSTimeoutError "message"
agfs::AGFSHTTPError "message" status_code
```

常用错误代码：
- 404 - 文件或目录不存在
- 403 - 权限拒绝
- 409 - 资源已存在
- 500 - 服务器内部错误
- 502 - 网关错误

## 许可证

AGFS项目的一部分。参见LICENSE文件。

## 贡献

欢迎贡献！请确保：
1. 运行测试脚本验证更改
2. 遵循Tcl编码风格
3. 更新文档

## 故障排除

**问题：无法连接到服务器**
```
Error: Connection refused - server not running
```
解决：确保AGFS服务器正在运行，并且URL正确。

**问题：模块未找到**
```
can't find package agfs
```
解决：将SDK目录添加到TCLLIBPATH或auto_path。

**问题：JSON解析错误**
```
Failed to parse JSON
```
解决：检查服务器响应是否为有效的JSON。

## 更多信息

- [AGFS Server](https://github.com/c4pt0r/agfs)
- [Python SDK](https://github.com/c4pt0r/agfs/tree/master/agfs-sdk/python)
- [Go SDK](https://github.com/c4pt0r/agfs/tree/master/agfs-sdk/go)
