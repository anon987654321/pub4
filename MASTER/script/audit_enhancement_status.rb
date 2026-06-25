#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"

ROOT = File.expand_path("..", __dir__)
FE_PATH = File.join(ROOT, "data/runtime/face_enhancements.yml")
MI_PATH = File.join(ROOT, "data/runtime/micro_interactions.yml")
F3D_PATH = File.join(ROOT, "data/runtime/face3d_migration.yml")

WEB_IMPLEMENTED = {
  "web_031" => "Message enter stagger delay up to 8 steps",
  "web_032" => "Typing indicator until first stream chunk",
  "web_033" => "Stream-live SR batched 120ms debounce",
  "web_034" => "Reaction chips persist via dataset.reaction",
  "web_035" => "User messages right-aligned reversed prompt",
  "web_036" => "Streaming cursor blink step fade on done",
  "web_037" => "Fenced code blocks during stream",
  "web_038" => "Dmesg accent lines 3-slot fade ring",
  "web_039" => "Message timestamp on hover data-ts",
  "web_040" => "Assistant confidence left-border band",
  "web_042" => "Edge-hover swipe reveals prompt bar",
  "web_043" => "Empty chat no-history ghost state",
  "web_046" => "Char count after 120 chars",
  "web_047" => "Listening mode saturates face canvas",
  "web_048" => "Cancel button pulses during thinking",
  "web_049" => "Idle help trail toward input after silence",
  "web_050" => "Speaking mode tints prompt prefix",
  "web_051" => "Prompt disabled until primer unlocks",
  "web_052" => "Self-violation canvas contrast flash",
  "web_053" => "Mid-stream tool-stack progress chip",
  "web_054" => "Uncertain verdict status blink",
  "web_055" => "Primer dismiss scale opacity fade",
  "web_056" => "Sleeping mode dims canvas and prompt",
  "web_057" => "Error mood-cold white-only indication",
  "web_058" => "TTS-loading status shimmer",
  "web_059" => "Pipeline-stage bar syncs to SSE stages",
  "web_060" => "Network stall tints status calms canvas",
  "web_061" => "Council persona badge via status rotator",
  "web_062" => "Particle worker warm-start on primer",
  "web_063" => "Visual governor caps FPS particle pressure",
  "web_064" => "Virtual scroll trims chat to 56 messages",
  "web_065" => "OffscreenCanvas ecology buffer",
  "web_066" => "Bridge RAF-batches rapid visual events",
  "web_067" => "Battery profile halves ecology agents",
  "web_068" => "Kernel frame dt clamp fixed timestep",
  "web_069" => "Canvas resize 50px threshold debounce",
  "web_070" => "Chat-append microtask queue",
  "web_071" => "Primer boot spawns attention kernel cells",
  "web_072" => "Hidden tab pauses face loop disconnects SSE",
  "web_073" => "Coarse pointer halves particle grid",
  "web_074" => "Activity-adaptive mood color lerp",
  "web_075" => "Dmesg shared 3-slot fade ring",
  "web_076" => "Per-message action bar assistant bubbles",
  "web_077" => "Session stats footer words elapsed",
  "web_078" => "Typing dots until stream chunks",
  "web_079" => "Collapsible thought-trace assistant",
  "web_080" => "Keyboard shortcut sheet cmd palette"
}.freeze

F3D_IMPLEMENTED = %w[f3d_006 f3d_007 f3d_008 f3d_009].freeze

def patch_list(path, list_key, implemented_map: {}, implemented_ids: [])
  data = YAML.safe_load_file(path, permitted_classes: [Symbol], aliases: true)
  changed = 0
  data[list_key].each do |item|
    id = item["id"].to_s
    next unless implemented_map.key?(id) || implemented_ids.include?(id)
    next if item["status"].to_s == "implemented"

    item["status"] = "implemented"
    item["summary"] = implemented_map[id] if implemented_map.key?(id)
    changed += 1
  end
  File.write(path, data.to_yaml(line_width: -1))
  [path, changed]
end

def sync_mi_from_canonical
  mi = YAML.safe_load_file(MI_PATH, permitted_classes: [Symbol], aliases: true)
  implemented_ids = Array(mi["interactions"]).select { |row| row["status"].to_s == "implemented" }.map { |row| row["id"].to_s }
  patch_list(FE_PATH, "enhancements", implemented_ids: implemented_ids.select { |id| id.start_with?("mi_") })
end

fe = patch_list(FE_PATH, "enhancements", implemented_map: WEB_IMPLEMENTED, implemented_ids: F3D_IMPLEMENTED)
f3d = patch_list(F3D_PATH, "migration_steps", implemented_ids: %w[step_6 step_7 step_8 step_9])

fe_pending = YAML.safe_load_file(FE_PATH, permitted_classes: [Symbol], aliases: true)["enhancements"].count { |r| r["status"].to_s == "pending" }
fe_impl = YAML.safe_load_file(FE_PATH, permitted_classes: [Symbol], aliases: true)["enhancements"].count { |r| r["status"].to_s == "implemented" }

puts "face_enhancements: #{fe[1]} updated → #{fe_impl} implemented / #{fe_pending} pending"
puts "face3d_migration: #{f3d[1]} steps updated"