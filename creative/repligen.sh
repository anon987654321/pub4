#!/usr/bin/env bash
# repligen.sh - Replicate.com CLI Wrapper (POSIX-compliant)
# Version: 2.0.0 - Zero-sprawl shell wrapper
#
# Usage:
#   ./repligen.sh                    # Interactive mode
#   ./repligen.sh sync 100           # Sync 100 models
#   ./repligen.sh masterpiece "..."  # Generate with prompt
#   ./repligen.sh chain 10 "..."     # Random chain
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPLIGEN_RB="$SCRIPT_DIR/repligen.rb"

# Color codes (POSIX-compatible)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  ${BLUE}REPLIGEN${NC} - Replicate.com AI Generation CLI              ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  Version 2.0.0 - Shell Wrapper + Ruby Engine              ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
}

check_prerequisites() {
    local missing=0
    
    # Check Ruby
    if ! command -v ruby >/dev/null 2>&1; then
        echo -e "${RED}❌ Ruby not found${NC}"
        echo "Install with: sudo apt install ruby (Debian/Ubuntu) or pkg_add ruby (OpenBSD)"
        missing=1
    else
        echo -e "${GREEN}✅ Ruby:${NC} $(ruby -v | cut -d' ' -f1-2)"
    fi
    
    # Check repligen.rb
    if [ ! -f "$REPLIGEN_RB" ]; then
        echo -e "${RED}❌ repligen.rb not found at $REPLIGEN_RB${NC}"
        missing=1
    fi
    
    # Check API token
    if [ -z "${REPLICATE_API_TOKEN:-}" ]; then
        echo -e "${YELLOW}⚠️  REPLICATE_API_TOKEN not set${NC}"
        echo "Set it with:"
        echo "  export REPLICATE_API_TOKEN='your_token_here'"
        echo "  # Add to ~/.profile or ~/.bashrc to persist"
        missing=1
    else
        echo -e "${GREEN}✅ API Token:${NC} ${REPLICATE_API_TOKEN:0:8}...${REPLICATE_API_TOKEN: -4}"
    fi
    
    # Check optional dependencies
    if command -v ffmpeg >/dev/null 2>&1; then
        echo -e "${GREEN}✅ ffmpeg:${NC} $(ffmpeg -version 2>/dev/null | head -n1 | cut -d' ' -f3)"
    else
        echo -e "${YELLOW}⚠️  ffmpeg not found (optional, for video processing)${NC}"
    fi
    
    [ $missing -eq 0 ] && return 0 || return 1
}

show_help() {
    cat << 'EOF'
Usage: ./repligen.sh [COMMAND] [ARGS...]

Commands:
  (none)                  Start interactive REPL
  sync [N]                Sync N models from Replicate.com (default: 50)
  search QUERY            Search local model database
  stats                   Show database statistics
  masterpiece PROMPT      Generate with intelligent chain selection
  chain N PROMPT          Run N-step random chain
  upscale FILE            Upscale an image
  animate FILE            Animate an image to video
  rembg FILE              Remove background from image
  lora URL1 URL2...       Train LoRA from image URLs

Examples:
  ./repligen.sh
  ./repligen.sh sync 100
  ./repligen.sh search "upscale"
  ./repligen.sh masterpiece "cyberpunk city at night, neon lights"
  ./repligen.sh chain 15 "abstract art"
  ./repligen.sh upscale myimage.jpg
  ./repligen.sh lora https://i.imgur.com/abc.jpg https://i.imgur.com/def.jpg

Environment Variables:
  REPLICATE_API_TOKEN     Your Replicate.com API token (required)
  REPLIGEN_DB             Database path (default: ./repligen.db)
  REPLIGEN_OUTPUT         Output directory (default: ./output)

Files:
  repligen.rb             Main Ruby engine
  repligen.db             SQLite model cache
  lora_masterpiece_workflow.sh    Full LoRA→generate→animate pipeline

Documentation:
  README.md               Full documentation
  USAGE.md                Usage examples and tips
EOF
}

run_interactive() {
    echo -e "${CYAN}Starting interactive mode...${NC}"
    echo "Type 'help' for commands, 'quit' to exit"
    echo ""
    exec ruby "$REPLIGEN_RB"
}

run_command() {
    local cmd="$1"
    shift
    
    case "$cmd" in
        help|--help|-h)
            show_help
            ;;
        sync)
            local count="${1:-50}"
            echo -e "${BLUE}Syncing $count models from Replicate.com...${NC}"
            ruby "$REPLIGEN_RB" sync "$count"
            ;;
        search)
            [ $# -eq 0 ] && { echo "Usage: repligen.sh search QUERY"; exit 1; }
            ruby "$REPLIGEN_RB" search "$@"
            ;;
        stats)
            ruby "$REPLIGEN_RB" stats
            ;;
        masterpiece)
            [ $# -eq 0 ] && { echo "Usage: repligen.sh masterpiece PROMPT"; exit 1; }
            echo -e "${BLUE}Generating masterpiece with prompt: $*${NC}"
            ruby "$REPLIGEN_RB" masterpiece "$@"
            ;;
        chain)
            [ $# -lt 2 ] && { echo "Usage: repligen.sh chain N PROMPT"; exit 1; }
            local steps="$1"
            shift
            echo -e "${BLUE}Running $steps-step chain: $*${NC}"
            ruby "$REPLIGEN_RB" chain "$steps" "$@"
            ;;
        upscale|animate|rembg)
            [ $# -eq 0 ] && { echo "Usage: repligen.sh $cmd FILE"; exit 1; }
            ruby "$REPLIGEN_RB" "$cmd" "$@"
            ;;
        lora)
            [ $# -eq 0 ] && { echo "Usage: repligen.sh lora URL1 URL2 [URL3...]"; exit 1; }
            echo -e "${BLUE}Training LoRA with $# images...${NC}"
            ruby "$REPLIGEN_RB" lora "$@"
            ;;
        *)
            echo -e "${RED}Unknown command: $cmd${NC}"
            echo "Run './repligen.sh help' for usage"
            exit 1
            ;;
    esac
}

main() {
    print_header
    
    if ! check_prerequisites; then
        echo ""
        echo -e "${RED}Fix issues above before continuing${NC}"
        exit 1
    fi
    
    echo ""
    
    if [ $# -eq 0 ]; then
        run_interactive
    else
        run_command "$@"
    fi
}

main "$@"
