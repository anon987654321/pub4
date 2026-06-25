#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"

ROOT = File.expand_path("..", __dir__)
FE_PATH = File.join(ROOT, "data/runtime/face_enhancements.yml")
MI_PATH = File.join(ROOT, "data/runtime/micro_interactions.yml")

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

MI_IMPLEMENTED = %w[
  mi_001 mi_002 mi_007 mi_013 mi_016 mi_018 mi_020 mi_027 mi_037 mi_038 mi_040
  mi_041 mi_044 mi_045 mi_049 mi_054 mi_059 mi_060 mi_068 mi_074 mi_077 mi_079
  mi_010 mi_032 mi_033 mi_034 mi_036 mi_065 mi_069 mi_053 mi_046 mi_043 mi_067
  mi_080 mi_075 mi_078 mi_076 mi_051 mi_057 mi_011
].freeze

def patch_file(path, key, implemented_map: {}, implemented_ids: [])
  data = YAML.safe_load_file(path, permitted_classes: [Symbol], aliases: true)
  list_key = data.key?("enhancements") ? "enhancements" : "interactions"
  changed = 0
  data[list_key].each do |item|
    id = item["id"].to_s
    if implemented_map.key?(id)
      item["status"] = "implemented"
      item["summary"] = implemented_map[id]
      changed += 1
    elsif implemented_ids.include?(id)
      item["status"] = "implemented"
      changed += 1
    end
  end
  File.write(path, data.to_yaml(line_width: -1))
  [path, changed]
end

fe = patch_file(FE_PATH, "enhancements", implemented_map: WEB_IMPLEMENTED)
mi = patch_file(MI_PATH, "interactions", implemented_ids: MI_IMPLEMENTED)
puts "face_enhancements: #{fe[1]} updated"
puts "micro_interactions: #{mi[1]} updated"