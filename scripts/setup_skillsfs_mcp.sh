#!/usr/bin/env bash
# Helper script to install/start the AGFS MCP server and register it with Claude Code.

set -euo pipefail

AGFS_MCP_DIR="${AGFS_MCP_DIR:-/Users/vajra/Clang/agfs/agfs-mcp}"
AGFS_SERVER_URL="${AGFS_SERVER_URL:-http://localhost:8080}"
SKILLS_BASE_PATH="${SKILLS_BASE_PATH:-/skills}"
CLAUDE_BIN="${CLAUDE_BIN:-claude}"

if [ ! -d "$AGFS_MCP_DIR" ]; then
  echo "Error: AGFS_MCP_DIR does not exist: $AGFS_MCP_DIR" >&2
  exit 1
fi

echo "[1/3] Installing/updating agfs-mcp via uv ..."
(
  cd "$AGFS_MCP_DIR"
  uv pip install -e .
)

echo "[2/3] Example command to run the MCP server manually:"
echo "AGFS_SERVER_URL=$AGFS_SERVER_URL SKILLS_BASE_PATH=$SKILLS_BASE_PATH uv run agfs-mcp"
echo

ADD_CMD=( "$CLAUDE_BIN" mcp add --transport stdio skillsfs
          --env "AGFS_SERVER_URL=$AGFS_SERVER_URL"
          --env "SKILLS_BASE_PATH=$SKILLS_BASE_PATH"
          -- /bin/sh -c "cd $AGFS_MCP_DIR && uv run agfs-mcp" )

echo "[3/3] Registering MCP server with Claude Code (skillsfs) ..."
if command -v "$CLAUDE_BIN" >/dev/null 2>&1; then
  if "${ADD_CMD[@]}"; then
    echo "Claude MCP server 'skillsfs' registered."
  else
    echo "Warning: Failed to register MCP server automatically. Run the following manually:" >&2
    printf '  %s\n' "${ADD_CMD[@]}" >&2
  fi
else
  echo "Claude CLI not found; run the following command manually to register:" >&2
  printf '  %s\n' "${ADD_CMD[@]}" >&2
fi

cat <<EOF
Done!
- To start the MCP server interactively:
    AGFS_SERVER_URL=$AGFS_SERVER_URL SKILLS_BASE_PATH=$SKILLS_BASE_PATH uv run agfs-mcp
- In Claude Code, look for tools prefixed with skill_* under the "skillsfs" server.
EOF
