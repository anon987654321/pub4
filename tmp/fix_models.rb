# encoding: utf-8
# frozen_string_literal: true
BASE = "/home/dev/pub4/MASTER"
path = File.join(BASE, "data/models.yml")
content = File.read(path, encoding: "utf-8")

# 1. Remove dead deepseek-r1-0528 model def and references
content.gsub!(/  deepseek_r1:.*?score:.*?\n/m, "") if content.include?("deepseek-r1-0528")
content.sub!(/  deepseek_r1: &deepseek_r1\n    id: deepseek\/deepseek-r1-0528:free\n    <<: \*model_defaults\n    score: \{ quality: 0\.73, speed: 0\.55, cost: 1\.0 \}\n/, "")

# 2. Remove from merged fallback section
content.gsub!(/\s*- deepseek\/deepseek-r1-0528:free\n/, "\n")

# 3. Add new strong free models
# Add minimax (large, capable) and hermes-3-405b
unless content.include?("minimax_m25")
  # Insert after gpt_oss definition
  insertion = <<~'YAML'
  minimax_m25: &minimax_m25
    id: minimax/minimax-m2.5:free
    <<: *model_defaults
    score: { quality: 0.82, speed: 0.65, cost: 1.0 }
  hermes_405b: &hermes_405b
    id: nousresearch/hermes-3-llama-3.1-405b:free
    <<: *model_defaults
    score: { quality: 0.85, speed: 0.50, cost: 1.0 }
  YAML
  content.sub!(/^  gpt_oss:.*?score:.*?\n/m) { |match| "#{match}#{insertion}" }
end

# 4. Update fallback chains to use live models
# default tier: nemotron-super -> qwen3-coder -> minimax -> gpt-oss -> gemini-flash
content.sub!(
  /^  default:\n(    - \*\w+\n)+/,
  "  default:\n    - *nemotron_super\n    - *qwen_coder\n    - *minimax_m25\n    - *gpt_oss\n    - *gemini_flash\n"
)

# strong tier: hermes-405b -> claude-sonnet -> gpt-4o -> nemotron-super -> gemini-flash
content.sub!(
  /^  strong:\n(    - \*\w+\n)+/,
  "  strong:\n    - *hermes_405b\n    - *claude_sonnet\n    - *gpt_4o\n    - *nemotron_super\n    - *gemini_flash\n"
)

# cheap tier: llama-70b -> qwen3-coder -> gpt-oss -> gemini-flash
content.sub!(
  /^  cheap:\n(    - \*\w+\n)+/,
  "  cheap:\n    - *llama_70b\n    - *qwen_coder\n    - *gpt_oss\n    - *gemini_flash\n"
)

# 5. Update merged fallback section
content.sub!(
  /openrouter:\n  free_latest:\n(    - .*\n)+/,
  "openrouter:\n  free_latest:\n    - nvidia/nemotron-3-super-120b-a12b:free\n    - qwen/qwen3-coder:free\n    - openai/gpt-oss-120b:free\n    - minimax/minimax-m2.5:free\n"
)

# 6. Also update default_model in config.rb since deepseek is gone
config_path = File.join(BASE, "lib/master/config.rb")
config = File.read(config_path, encoding: "utf-8")
if config.include?("meta-llama/llama-3.3-70b-instruct:free")
  config.sub!("meta-llama/llama-3.3-70b-instruct:free", "nvidia/nemotron-3-super-120b-a12b:free")
  File.write(config_path, config)
  puts "config.rb: default model -> nemotron-super"
end

File.write(path, content)
puts "models.yml: removed dead deepseek-r1, added minimax + hermes-405b, updated chains"
