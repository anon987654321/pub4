#!/bin/sh
# Clone the upstream references data/runtime.yml names, for local study and
# for SearchKnowledge offline (knowledge/ is gitignored): style_guides into
# knowledge/style_guides/, offline_knowledge repos into knowledge/<topic>/,
# and its papers' ar5iv pages into knowledge/research/. The catalog is the
# list; this script holds none of its own.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

clone_or_pull() {
  url="$1"
  dir="$2"
  if [ -d "$dir/.git" ]; then
    git -C "$dir" pull --ff-only
  else
    mkdir -p "$(dirname "$dir")"
    git clone --depth 1 "$url" "$dir"
  fi
}

ruby -ryaml -e '
  cat = YAML.load_file("data/runtime.yml", aliases: true)
  cat.fetch("style_guides").fetch("sources").each { |s| puts "repo #{s["repo"]} knowledge/style_guides/#{s["local"]}" }
  cat.fetch("offline_knowledge").fetch("sources").each { |s| puts "repo #{s["repo"]} knowledge/#{s["topic"]}/#{s["local"]}" }
  cat.fetch("offline_knowledge").fetch("papers").each { |p| puts "paper https://ar5iv.labs.arxiv.org/html/#{p["id"]} knowledge/research/#{p["id"]}.html" }
' | while read -r kind url dest; do
  if [ "$kind" = repo ]; then
    clone_or_pull "$url" "$dest"
  elif [ ! -s "$dest" ]; then
    mkdir -p "$(dirname "$dest")"
    curl -fsSL "$url" -o "$dest"
  fi
done

echo "references ready under $ROOT/knowledge"
