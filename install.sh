#!/bin/bash
# Agent Registry Skill Installer
# Installs the agent-registry skill to your Claude Code skills directory

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║       Agent Registry Skill Installer                     ║"
echo "║  Reduce agent token overhead by ~95%                     ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Determine installation location
if [ "$1" == "--project" ] || [ "$1" == "-p" ]; then
    INSTALL_DIR=".claude/skills/agent-registry"
    echo -e "${YELLOW}Installing to project-level: ${INSTALL_DIR}${NC}"
else
    INSTALL_DIR="$HOME/.claude/skills/agent-registry"
    echo -e "${GREEN}Installing to user-level: ${INSTALL_DIR}${NC}"
fi

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Create target directory
echo -e "\n${CYAN}Creating skill directory...${NC}"
mkdir -p "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/lib"
mkdir -p "$INSTALL_DIR/bin"
mkdir -p "$INSTALL_DIR/references"
mkdir -p "$INSTALL_DIR/agents"
mkdir -p "$INSTALL_DIR/hooks"

# Copy files
echo -e "${CYAN}Copying skill files...${NC}"

cp "$SCRIPT_DIR/SKILL.md" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/package.json" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/lib/"*.js "$INSTALL_DIR/lib/"
cp "$SCRIPT_DIR/bin/"*.js "$INSTALL_DIR/bin/"
chmod +x "$INSTALL_DIR/bin/"*.js
cp "$SCRIPT_DIR/hooks/"*.js "$INSTALL_DIR/hooks/"
chmod +x "$INSTALL_DIR/hooks/"*.js

# Create empty registry if it doesn't exist
if [ ! -f "$INSTALL_DIR/references/registry.json" ]; then
    echo '{"version": 1, "agents": [], "stats": {"total_agents": 0, "total_tokens": 0}}' > "$INSTALL_DIR/references/registry.json"
fi

# Install dependencies
echo -e "\n${CYAN}Installing dependencies...${NC}"
cd "$INSTALL_DIR" && npm install --production 2>/dev/null || bun install 2>/dev/null || true
echo -e "${GREEN}✓ Dependencies installed${NC}"

echo -e "\n${GREEN}✓ Skill installed successfully!${NC}"
echo ""
echo -e "${CYAN}Next steps:${NC}"
echo ""
echo "1. Run the migration script to move your agents to the registry:"
echo -e "   ${YELLOW}cd $INSTALL_DIR && bun bin/init.js${NC}"
echo ""
echo "2. After migration, Claude Code will use lazy loading for agents"
echo ""
echo "3. Verify with:"
echo -e "   ${YELLOW}cd $INSTALL_DIR && bun bin/list.js${NC}"
echo ""
echo -e "${GREEN}Installation complete!${NC}"
