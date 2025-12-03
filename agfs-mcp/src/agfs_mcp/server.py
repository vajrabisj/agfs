#!/usr/bin/env python3
"""AGFS MCP Server - Expose AGFS operations through Model Context Protocol"""

import json
import logging
import os
from typing import Any, Optional
from mcp.server import Server
from mcp.types import Tool, TextContent, Prompt, PromptMessage
from pyagfs import AGFSClient, AGFSClientError, cp, upload, download

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("agfs-mcp")


class AGFSMCPServer:
    """MCP Server for AGFS operations"""

    def __init__(
        self,
        agfs_url: str = "http://localhost:8080/api/v1",
        skills_base: Optional[str] = None,
    ):
        self.server = Server("agfs-mcp")
        self.agfs_url = agfs_url
        self.client: Optional[AGFSClient] = None
        self.skills_base = skills_base or os.environ.get("SKILLS_BASE_PATH", "/skills")
        if self.skills_base == "":
            self.skills_base = None
        elif self.skills_base and not self.skills_base.startswith("/"):
            self.skills_base = "/" + self.skills_base
        self.skill_tool_map: dict[str, dict[str, str]] = {}
        self._setup_handlers()

    def _get_client(self) -> AGFSClient:
        """Get or create AGFS client"""
        if self.client is None:
            self.client = AGFSClient(self.agfs_url)
        return self.client

    def _safe_cat(self, path: str) -> str:
        """Read file content, returning empty string on failure"""
        try:
            data = self._get_client().cat(path)
            if isinstance(data, bytes):
                return data.decode("utf-8", errors="replace")
            return data
        except AGFSClientError as exc:
            logger.debug("Failed to read %s: %s", path, exc)
            return ""

    def _discover_skills(self) -> list[dict[str, str]]:
        """Discover skills mounted under skills_base"""
        self.skill_tool_map = {}
        if not self.skills_base:
            return []
        try:
            entries = self._get_client().ls(self.skills_base)
        except AGFSClientError as exc:
            logger.debug("Skills discovery failed: %s", exc)
            return []

        skills: list[dict[str, str]] = []
        for entry in entries:
            if not entry.get("isDir"):
                continue
            name = entry.get("name") or entry.get("path") or "skill"
            skill_path = f"{self.skills_base.rstrip('/')}/{name}"
            metadata = self._safe_cat(f"{skill_path}/metadata").strip()
            instructions = self._safe_cat(f"{skill_path}/instructions").strip()

            safe_base = "".join(ch if ch.isalnum() else "_" for ch in name.lower()).strip("_")
            safe_name = f"skill_{safe_base}" if safe_base else f"skill_{len(skills)+1}"
            suffix = 1
            while safe_name in self.skill_tool_map:
                suffix += 1
                safe_name = f"{safe_name}_{suffix}"

            desc_parts = []
            if metadata:
                desc_parts.append(metadata)
            if instructions:
                snippet = instructions[:300]
                if len(instructions) > 300:
                    snippet += "..."
                desc_parts.append(f"Instructions: {snippet}")
            description = " | ".join(desc_parts) if desc_parts else "SkillsFS action"

            info = {
                "tool_name": safe_name,
                "path": skill_path,
                "display_name": name,
                "description": description,
            }
            self.skill_tool_map[safe_name] = info
            skills.append(info)

        return skills

    def _get_skill_info(self, tool_name: str) -> Optional[dict[str, str]]:
        """Return skill info, refreshing discovery if necessary"""
        skill = self.skill_tool_map.get(tool_name)
        if skill:
            return skill
        # Refresh discovery in case new skills were mounted
        self._discover_skills()
        return self.skill_tool_map.get(tool_name)

    def _setup_handlers(self):
        """Setup MCP request handlers"""

        @self.server.list_prompts()
        async def list_prompts() -> list[Prompt]:
            """List available prompts"""
            return [
                Prompt(
                    name="agfs_introduction",
                    description="Introduction to AGFS (Agent File System) - core concepts and architecture"
                )
            ]

        @self.server.get_prompt()
        async def get_prompt(name: str, arguments: dict[str, str] | None = None) -> PromptMessage:
            """Get prompt content"""
            if name == "agfs_introduction":
                return PromptMessage(
                    role="user",
                    content=TextContent(
                        type="text",
                        text="""# AGFS (Agent File System) - Introduction

## Overview
AGFS Server is a RESTful file system server inspired by Plan9 that leverages a powerful plugin architecture. It exposes various services—including message queues, key-value stores, databases, and remote systems—through a unified virtual file system interface.

## Core Philosophy
The system follows the Unix philosophy of "everything is a file" but extends it to modern cloud services and data stores. By representing diverse backend services as file hierarchies, AGFS provides a consistent, intuitive interface for accessing heterogeneous systems.

## Key Features

### Plugin Architecture
The system allows mounting multiple filesystems and services at different paths, enabling flexible service composition. Each plugin implements the filesystem interface but can represent any kind of backend service.

### External Plugin Support
Plugins load dynamically from:
- Shared libraries (.so on Linux, .dylib on macOS, .dll on Windows)
- WebAssembly modules (.wasm)
- HTTP(S) URLs for remote plugin loading

This enables extending AGFS without server recompilation or restart.

### Unified API
A single HTTP REST interface handles operations across all mounted plugins:
- GET /api/v1/files?path=/xxx - Read file content
- PUT /api/v1/files?path=/xxx - Write file content
- GET /api/v1/directories?path=/xxx - List directory
- POST /api/v1/directories?path=/xxx - Create directory
- DELETE /api/v1/files?path=/xxx - Remove file/directory
- GET /api/v1/stat?path=/xxx - Get file info
- POST /api/v1/rename - Move/rename file
- POST /api/v1/grep - Search in files

### Dynamic Management
Plugins can be managed at runtime via API:
- Mount/unmount plugins at any path
- Load/unload external plugins
- Configure multiple instances of the same plugin type
- Query mounted plugins and their configurations

### Multi-Instance Capability
The same plugin type can run multiple independent instances. For example:
- Multiple database connections at /db/users, /db/products, /db/logs
- Multiple S3 buckets at /s3/backup, /s3/public, /s3/archive
- Multiple remote servers federated at /remote/server1, /remote/server2

## Architecture

```
┌─────────────────────────────────────────────┐
│           HTTP REST API (Port 8080)         │
│          /api/v1/files, /directories        │
└───────────────────┬─────────────────────────┘
                    │
         ┌──────────▼──────────┐
         │    MountableFS      │  ← Central router
         │  (Path → Plugin)    │
         └──────────┬──────────┘
                    │
        ┌───────────┴───────────┐
        │                       │
   ┌────▼─────┐          ┌─────▼────┐
   │ Built-in │          │ External │
   │ Plugins  │          │ Plugins  │
   └────┬─────┘          └─────┬────┘
        │                      │
   ┌────▼──────────────────────▼────┐
   │ QueueFS, KVFS, MemFS, SQLFS,  │
   │ ProxyFS, S3FS, LocalFS, etc.  │
   └───────────────────────────────┘
```

The MountableFS layer routes requests to the appropriate plugin based on the requested path, enabling seamless integration of multiple services.

## Built-in Plugins

- **QueueFS**: Message queue operations via files (publish/subscribe)
- **KVFS**: Key-value data storage (simple get/set operations)
- **MemFS**: In-memory temporary storage (fast, volatile)
- **SQLFS**: Database-backed operations (persistent, queryable)
- **ProxyFS**: Remote server federation (mount remote AGFS servers)
- **S3FS**: S3-compatible object storage integration
- **LocalFS**: Local filesystem access
- **HTTPFS**: HTTP-based file access

## Common Use Cases

1. **Unified Data Access**: Access databases, object storage, and local files through a single interface
2. **Service Composition**: Combine multiple data sources at different mount points
3. **Remote Federation**: Mount remote AGFS servers as local directories
4. **Plugin Development**: Extend functionality with custom plugins (WebAssembly, shared libraries)
5. **Streaming Operations**: Stream large files or continuous data (logs, metrics)
6. **Pattern Matching**: Use grep for searching across different backends

## Working with AGFS via MCP

When using AGFS through this MCP server, you have access to all these capabilities through simple tool calls. Each tool operation maps to the AGFS REST API, allowing you to:
- Navigate mounted plugins as directory hierarchies
- Read/write data across different backend services
- Search for patterns using grep
- Manage plugin lifecycle (mount/unmount)
- Monitor system health

The key insight is that whether you're reading from a SQL database at /db/users/data, an S3 bucket at /s3/logs/2024.txt, or a local file at /local/config.json, you use the same consistent file operations."""
                    )
                )
            raise ValueError(f"Unknown prompt: {name}")

        @self.server.list_tools()
        async def list_tools() -> list[Tool]:
            """List available AGFS tools (including SkillsFS tools)"""
            tools: list[Tool] = [
                Tool(
                    name="agfs_ls",
                    description="List directory contents in AGFS",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "path": {
                                "type": "string",
                                "description": "Directory path to list (default: /)",
                                "default": "/"
                            }
                        }
                    }
                ),
                Tool(
                    name="agfs_cat",
                    description="Read file content from AGFS",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "path": {
                                "type": "string",
                                "description": "File path to read"
                            },
                            "offset": {
                                "type": "integer",
                                "description": "Starting offset (default: 0)",
                                "default": 0
                            },
                            "size": {
                                "type": "integer",
                                "description": "Number of bytes to read (default: -1 for all)",
                                "default": -1
                            }
                        },
                        "required": ["path"]
                    }
                ),
                Tool(
                    name="agfs_write",
                    description="Write content to a file in AGFS",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "path": {
                                "type": "string",
                                "description": "File path to write to"
                            },
                            "content": {
                                "type": "string",
                                "description": "Content to write to the file"
                            }
                        },
                        "required": ["path", "content"]
                    }
                ),
                Tool(
                    name="agfs_mkdir",
                    description="Create a directory in AGFS",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "path": {
                                "type": "string",
                                "description": "Directory path to create"
                            },
                            "mode": {
                                "type": "string",
                                "description": "Permissions mode (default: 755)",
                                "default": "755"
                            }
                        },
                        "required": ["path"]
                    }
                ),
                Tool(
                    name="agfs_rm",
                    description="Remove a file or directory from AGFS",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "path": {
                                "type": "string",
                                "description": "Path to remove"
                            },
                            "recursive": {
                                "type": "boolean",
                                "description": "Remove directories recursively (default: false)",
                                "default": False
                            }
                        },
                        "required": ["path"]
                    }
                ),
                Tool(
                    name="agfs_stat",
                    description="Get file or directory information from AGFS",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "path": {
                                "type": "string",
                                "description": "Path to get information about"
                            }
                        },
                        "required": ["path"]
                    }
                ),
                Tool(
                    name="agfs_mv",
                    description="Move or rename a file/directory in AGFS",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "old_path": {
                                "type": "string",
                                "description": "Source path"
                            },
                            "new_path": {
                                "type": "string",
                                "description": "Destination path"
                            }
                        },
                        "required": ["old_path", "new_path"]
                    }
                ),
                Tool(
                    name="agfs_grep",
                    description="Search for pattern in files using regular expressions",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "path": {
                                "type": "string",
                                "description": "Path to search in (file or directory)"
                            },
                            "pattern": {
                                "type": "string",
                                "description": "Regular expression pattern to search for"
                            },
                            "recursive": {
                                "type": "boolean",
                                "description": "Search recursively in directories (default: false)",
                                "default": False
                            },
                            "case_insensitive": {
                                "type": "boolean",
                                "description": "Case-insensitive search (default: false)",
                                "default": False
                            }
                        },
                        "required": ["path", "pattern"]
                    }
                ),
                Tool(
                    name="agfs_mounts",
                    description="List all mounted plugins in AGFS",
                    inputSchema={
                        "type": "object",
                        "properties": {}
                    }
                ),
                Tool(
                    name="agfs_mount",
                    description="Mount a plugin in AGFS",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "fstype": {
                                "type": "string",
                                "description": "Filesystem type (e.g., 'sqlfs', 'memfs', 's3fs')"
                            },
                            "path": {
                                "type": "string",
                                "description": "Mount path"
                            },
                            "config": {
                                "type": "object",
                                "description": "Plugin configuration (varies by fstype)",
                                "default": {}
                            }
                        },
                        "required": ["fstype", "path"]
                    }
                ),
                Tool(
                    name="agfs_unmount",
                    description="Unmount a plugin from AGFS",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "path": {
                                "type": "string",
                                "description": "Mount path to unmount"
                            }
                        },
                        "required": ["path"]
                    }
                ),
                Tool(
                    name="agfs_health",
                    description="Check AGFS server health status",
                    inputSchema={
                        "type": "object",
                        "properties": {}
                    }
                ),
                Tool(
                    name="agfs_cp",
                    description="Copy a file or directory within AGFS",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "src": {
                                "type": "string",
                                "description": "Source path in AGFS"
                            },
                            "dst": {
                                "type": "string",
                                "description": "Destination path in AGFS"
                            },
                            "recursive": {
                                "type": "boolean",
                                "description": "Copy directories recursively (default: false)",
                                "default": False
                            },
                            "stream": {
                                "type": "boolean",
                                "description": "Use streaming for large files (default: false)",
                                "default": False
                            }
                        },
                        "required": ["src", "dst"]
                    }
                ),
                Tool(
                    name="agfs_upload",
                    description="Upload a file or directory from local filesystem to AGFS",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "local_path": {
                                "type": "string",
                                "description": "Path to local file or directory"
                            },
                            "remote_path": {
                                "type": "string",
                                "description": "Destination path in AGFS"
                            },
                            "recursive": {
                                "type": "boolean",
                                "description": "Upload directories recursively (default: false)",
                                "default": False
                            },
                            "stream": {
                                "type": "boolean",
                                "description": "Use streaming for large files (default: false)",
                                "default": False
                            }
                        },
                        "required": ["local_path", "remote_path"]
                    }
                ),
                Tool(
                    name="agfs_download",
                    description="Download a file or directory from AGFS to local filesystem",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "remote_path": {
                                "type": "string",
                                "description": "Path in AGFS"
                            },
                            "local_path": {
                                "type": "string",
                                "description": "Destination path on local filesystem"
                            },
                            "recursive": {
                                "type": "boolean",
                                "description": "Download directories recursively (default: false)",
                                "default": False
                            },
                            "stream": {
                                "type": "boolean",
                                "description": "Use streaming for large files (default: false)",
                                "default": False
                            }
                        },
                        "required": ["remote_path", "local_path"]
                    }
                ),
                Tool(
                    name="agfs_notify",
                    description="Send a notification message via QueueFS. Creates sender/receiver queues if they don't exist. Message is sent as JSON with from_name, message, and timestamp fields.",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "queuefs_root": {
                                "type": "string",
                                "description": "Root path of QueueFS mount (default: /queuefs)",
                                "default": "/queuefs"
                            },
                            "to": {
                                "type": "string",
                                "description": "Target queue name (receiver)"
                            },
                            "from": {
                                "type": "string",
                                "description": "Source queue name (sender)"
                            },
                            "data": {
                                "type": "string",
                                "description": "Message content to send (will be wrapped in JSON with from_name for callback)"
                            }
                        },
                        "required": ["to", "from", "data"]
                    }
                ),
            ]
            for skill in self._discover_skills():
                tools.append(
                    Tool(
                        name=skill["tool_name"],
                        description=f"SkillsFS: {skill['description']}",
                        inputSchema={
                            "type": "object",
                            "properties": {
                                "params": {
                                    "description": "JSON or plain text payload to write to /execute",
                                    "oneOf": [
                                        {"type": "string"},
                                        {"type": "object"},
                                        {"type": "array"},
                                    ],
                                },
                                "refresh": {
                                    "type": "boolean",
                                    "description": "If true, force a fresh execution even if cache is valid",
                                    "default": False,
                                },
                            },
                            "required": ["params"],
                        },
                    )
                )
            return tools

        @self.server.call_tool()
        async def call_tool(name: str, arguments: Any) -> list[TextContent]:
            """Handle tool calls"""
            try:
                client = self._get_client()

                if name == "agfs_ls":
                    path = arguments.get("path", "/")
                    result = client.ls(path)
                    return [TextContent(
                        type="text",
                        text=json.dumps(result, indent=2, ensure_ascii=False)
                    )]

                elif name == "agfs_cat":
                    path = arguments["path"]
                    offset = arguments.get("offset", 0)
                    size = arguments.get("size", -1)
                    content = client.cat(path, offset=offset, size=size)
                    # Try to decode as UTF-8, fallback to base64 for binary
                    try:
                        text = content.decode('utf-8')
                    except UnicodeDecodeError:
                        import base64
                        text = f"[Binary content, base64 encoded]\n{base64.b64encode(content).decode('ascii')}"
                    return [TextContent(type="text", text=text)]

                elif name == "agfs_write":
                    path = arguments["path"]
                    content = arguments["content"]
                    result = client.write(path, content.encode('utf-8'))
                    return [TextContent(type="text", text=result)]

                elif name == "agfs_mkdir":
                    path = arguments["path"]
                    mode = arguments.get("mode", "755")
                    result = client.mkdir(path, mode=mode)
                    return [TextContent(
                        type="text",
                        text=json.dumps(result, indent=2)
                    )]

                elif name == "agfs_rm":
                    path = arguments["path"]
                    recursive = arguments.get("recursive", False)
                    result = client.rm(path, recursive=recursive)
                    return [TextContent(
                        type="text",
                        text=json.dumps(result, indent=2)
                    )]

                elif name == "agfs_stat":
                    path = arguments["path"]
                    result = client.stat(path)
                    return [TextContent(
                        type="text",
                        text=json.dumps(result, indent=2)
                    )]

                elif name == "agfs_mv":
                    old_path = arguments["old_path"]
                    new_path = arguments["new_path"]
                    result = client.mv(old_path, new_path)
                    return [TextContent(
                        type="text",
                        text=json.dumps(result, indent=2)
                    )]

                elif name == "agfs_grep":
                    path = arguments["path"]
                    pattern = arguments["pattern"]
                    recursive = arguments.get("recursive", False)
                    case_insensitive = arguments.get("case_insensitive", False)
                    result = client.grep(
                        path,
                        pattern,
                        recursive=recursive,
                        case_insensitive=case_insensitive
                    )
                    return [TextContent(
                        type="text",
                        text=json.dumps(result, indent=2, ensure_ascii=False)
                    )]

                elif name == "agfs_mounts":
                    result = client.mounts()
                    return [TextContent(
                        type="text",
                        text=json.dumps(result, indent=2)
                    )]

                elif name == "agfs_mount":
                    fstype = arguments["fstype"]
                    path = arguments["path"]
                    config = arguments.get("config", {})
                    result = client.mount(fstype, path, config)
                    return [TextContent(
                        type="text",
                        text=json.dumps(result, indent=2)
                    )]

                elif name == "agfs_unmount":
                    path = arguments["path"]
                    result = client.unmount(path)
                    return [TextContent(
                        type="text",
                        text=json.dumps(result, indent=2)
                    )]

                elif name == "agfs_health":
                    result = client.health()
                    return [TextContent(
                        type="text",
                        text=json.dumps(result, indent=2)
                    )]

                elif name == "agfs_cp":
                    src = arguments["src"]
                    dst = arguments["dst"]
                    recursive = arguments.get("recursive", False)
                    stream = arguments.get("stream", False)
                    cp(client, src, dst, recursive=recursive, stream=stream)
                    return [TextContent(
                        type="text",
                        text=f"Successfully copied {src} to {dst}"
                    )]

                elif name == "agfs_upload":
                    local_path = arguments["local_path"]
                    remote_path = arguments["remote_path"]
                    recursive = arguments.get("recursive", False)
                    stream = arguments.get("stream", False)
                    upload(client, local_path, remote_path, recursive=recursive, stream=stream)
                    return [TextContent(
                        type="text",
                        text=f"Successfully uploaded {local_path} to {remote_path}"
                    )]

                elif name == "agfs_download":
                    remote_path = arguments["remote_path"]
                    local_path = arguments["local_path"]
                    recursive = arguments.get("recursive", False)
                    stream = arguments.get("stream", False)
                    download(client, remote_path, local_path, recursive=recursive, stream=stream)
                    return [TextContent(
                        type="text",
                        text=f"Successfully downloaded {remote_path} to {local_path}"
                    )]

                elif name == "agfs_notify":
                    from datetime import datetime, timezone

                    queuefs_root = arguments.get("queuefs_root", "/queuefs")
                    to = arguments["to"]
                    from_name = arguments["from"]
                    data = arguments["data"]

                    # Ensure queuefs_root doesn't end with /
                    queuefs_root = queuefs_root.rstrip('/')

                    # Create sender queue if it doesn't exist
                    from_queue_path = f"{queuefs_root}/{from_name}"
                    try:
                        client.stat(from_queue_path)
                    except AGFSClientError:
                        # Queue doesn't exist, create it
                        client.mkdir(from_queue_path)
                        logger.info(f"Created sender queue: {from_queue_path}")

                    # Create receiver queue if it doesn't exist
                    to_queue_path = f"{queuefs_root}/{to}"
                    try:
                        client.stat(to_queue_path)
                    except AGFSClientError:
                        # Queue doesn't exist, create it
                        client.mkdir(to_queue_path)
                        logger.info(f"Created receiver queue: {to_queue_path}")

                    # Wrap the message in JSON format with from_name for callback
                    message_json = {
                        "from": from_name,
                        "to": to,
                        "message": data,
                        "timestamp": datetime.now(timezone.utc).isoformat()
                    }
                    message_data = json.dumps(message_json, ensure_ascii=False)

                    # Send the notification by writing to receiver's enqueue file
                    enqueue_path = f"{to_queue_path}/enqueue"
                    client.write(enqueue_path, message_data.encode('utf-8'))

                    return [TextContent(
                        type="text",
                        text=f"Successfully sent notification from '{from_name}' to '{to}' queue"
                    )]

                else:
                    skill_info = self._get_skill_info(name)
                    if skill_info:
                        params = arguments.get("params")
                        if params is None:
                            raise ValueError("params is required for skill invocation")
                        if isinstance(params, (dict, list)):
                            payload = json.dumps(params, ensure_ascii=False)
                        else:
                            payload = str(params)
                        skill_path = skill_info["path"]
                        client.write(f"{skill_path}/execute", payload.encode("utf-8"))
                        result = self._safe_cat(f"{skill_path}/result") or "(empty result)"
                        status = self._safe_cat(f"{skill_path}/status") or "(no status info)"
                        response = (
                            f"Skill: {skill_info['display_name']} ({skill_path})\n"
                            f"Payload: {payload}\n\n"
                            f"Result:\n{result}\n\n"
                            f"Status:\n{status}"
                        )
                        return [TextContent(type="text", text=response)]

                    return [TextContent(
                        type="text",
                        text=f"Unknown tool: {name}"
                    )]

            except AGFSClientError as e:
                logger.error(f"AGFS error in {name}: {e}")
                return [TextContent(
                    type="text",
                    text=f"Error: {str(e)}"
                )]
            except Exception as e:
                logger.error(f"Unexpected error in {name}: {e}", exc_info=True)
                return [TextContent(
                    type="text",
                    text=f"Unexpected error: {str(e)}"
                )]

    async def run(self):
        """Run the MCP server"""
        from mcp.server.stdio import stdio_server

        async with stdio_server() as (read_stream, write_stream):
            await self.server.run(
                read_stream,
                write_stream,
                self.server.create_initialization_options()
            )


async def main():
    """Main entry point"""
    import os
    import sys

    # Get AGFS server URL from environment or use default
    agfs_url = os.getenv("AGFS_SERVER_URL", "http://localhost:8080")

    logger.info(f"Starting AGFS MCP Server (connecting to {agfs_url})")

    server = AGFSMCPServer(agfs_url)
    await server.run()


def cli():
    """CLI entry point for package script"""
    import asyncio
    asyncio.run(main())


if __name__ == "__main__":
    import asyncio
    asyncio.run(main())
