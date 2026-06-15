#!/usr/bin/env zsh
# Copy critical predecessor logic into DEPLOY/__predecessors/ for recovery reference.
# Sources default to the pub-compare clones; override with PUB_COMPARE_ROOT.
set -euo pipefail

SCRIPT_DIR=${0:a:h}
DEPLOY_ROOT=${SCRIPT_DIR:h}
OUT_ROOT=${DEPLOY_ROOT}/__predecessors
: "${PUB_COMPARE_ROOT:=${HOME}/Documents/GitHub/pub-compare}"

log() { printf '[sync_predecessors] %s\n' "$*" }

copy_tree() {
  local src="$1" dest="$2"
  [[ -d $src ]] || { log "skip missing: $src"; return 0; }
  mkdir -p "${dest:h}"
  rsync -a --delete "${src}/" "${dest}/"
  log "synced ${src} → ${dest}"
}

copy_file() {
  local src="$1" dest="$2"
  [[ -f $src ]] || { log "skip missing: $src"; return 0; }
  mkdir -p "${dest:h}"
  cp -f "$src" "$dest"
  log "copied ${src}"
}

[[ -d $PUB_COMPARE_ROOT ]] || {
  print -u2 "PUB_COMPARE_ROOT not found: $PUB_COMPARE_ROOT"
  print -u2 "Clone pub, pub2, pub3 first or set PUB_COMPARE_ROOT."
  exit 1
}

mkdir -p "$OUT_ROOT"

# Whole-app installers (no pub4 DEPLOY/rails trees yet)
copy_file "${PUB_COMPARE_ROOT}/pub3/rails/privcam.sh"      "${OUT_ROOT}/pub3-installers/privcam.sh"
copy_file "${PUB_COMPARE_ROOT}/pub3/rails/pub_attorney.sh" "${OUT_ROOT}/pub3-installers/pub_attorney.sh"
copy_file "${PUB_COMPARE_ROOT}/pub3/rails/mytoonz.sh"      "${OUT_ROOT}/pub3-installers/mytoonz.sh"
copy_tree  "${PUB_COMPARE_ROOT}/pub3/rails/__shared"       "${OUT_ROOT}/pub3-installers/__shared"

# AI orchestration
copy_tree "${PUB_COMPARE_ROOT}/pub2/aight/lib"             "${OUT_ROOT}/pub2-aight/lib"
copy_tree "${PUB_COMPARE_ROOT}/pub/ai3"                    "${OUT_ROOT}/pub-ai3"

# Multimedia / TTS
copy_tree "${PUB_COMPARE_ROOT}/pub3/multimedia/tts"        "${OUT_ROOT}/pub3-multimedia/tts"
copy_file "${PUB_COMPARE_ROOT}/pub3/multimedia/repligen.rb" "${OUT_ROOT}/pub3-multimedia/repligen.rb" 2>/dev/null || true
copy_tree "${PUB_COMPARE_ROOT}/pub3/multimedia/repligen"   "${OUT_ROOT}/pub3-multimedia/repligen"

# blognet AI builder
copy_file "${PUB_COMPARE_ROOT}/pub2/rails/build_blognet.rb" "${OUT_ROOT}/pub2-rails/build_blognet.rb"

log "writing gap_manifest.json"
cat > "${OUT_ROOT}/gap_manifest.json" <<'JSON'
{
  "updated": "2026-06-15",
  "archived_apps": [
    {
      "name": "privcam",
      "status": "installer_only",
      "recovery_source": "pub3-installers/privcam.sh",
      "notes": "Video upload, infinite scroll reflexes, comments"
    },
    {
      "name": "pub_attorney",
      "status": "installer_only",
      "recovery_source": "pub3-installers/pub_attorney.sh",
      "notes": "Lawyer/Case/Document, CaseMatchReflex, wicked_pdf"
    },
    {
      "name": "mytoonz",
      "status": "installer_only",
      "recovery_source": "pub3-installers/mytoonz.sh",
      "notes": "ReplicateService, comic strip jobs"
    }
  ],
  "archived_subsystems": [
    {
      "name": "aight_production_ai",
      "recovery_source": "pub2-aight/lib",
      "notes": "RAG, weaviate, scraper, assistant_orchestrator"
    },
    {
      "name": "ai3_assistants",
      "recovery_source": "pub-ai3",
      "notes": "57 assistants, cognitive_orchestrator, langchainrb"
    },
    {
      "name": "multimedia_tts",
      "recovery_source": "pub3-multimedia/tts",
      "notes": "Piper/Sherpa/Kokoro, claude_speak, narrate_reasoning"
    },
    {
      "name": "blognet_ai_content",
      "recovery_source": "pub2-rails/build_blognet.rb",
      "notes": "AiContentService, ai_generated column"
    },
    {
      "name": "shared_installer_patterns",
      "recovery_source": "pub3-installers/__shared",
      "notes": "InfiniteScrollReflex, AnonymousPostService, messenger disappearing messages"
    }
  ],
  "deployed_apps": ["brgen", "amber", "baibl", "blognet", "bsdports", "hjerterom"]
}
JSON

log "done → ${OUT_ROOT}"