#!/usr/bin/env ruby
# frozen_string_literal: true

ROOT = File.expand_path("..", __dir__)
MASTER = File.join(ROOT, "MASTER")

checks = {
  "MASTER/lib/voice/speech.rb" => [
    "def edge_tts_available?",
    "def espeak_path",
    "synthesize_espeak(text_str) if espeak_path"
  ],
  "MASTER/lib/voice/tts_supervisor.rb" => [
    "BUNDLE_ISOLATION_KEYS",
    "BUNDLE_ISOLATION_KEYS.each { |key| env[key] = nil }"
  ],
  "MASTER/bin/tts-worker" => [
    "tts-worker --daemon",
    "EventMachine SSL support unavailable",
    "BUNDLE_ISOLATION_KEYS.each { |key| ENV.delete(key) }"
  ],
  "MASTER/bin/smoke" => [
    "tts_e2e poll",
    "tts_e2e"
  ],
  "OPENBSD/OPERATOR.sh" => [
    "espeak"
  ],
  "OPENBSD/etc/rc.d/master" => [
    "Master::Voice::TtsSupervisor.ensure_daemon!",
    "MASTER_TTS_TIMEOUT=45"
  ]
}.freeze

failures = []

checks.each do |relative_path, needles|
  path = File.join(ROOT, relative_path)
  unless File.file?(path)
    failures << "missing #{relative_path}"
    next
  end

  body = File.read(path)
  needles.each do |needle|
    failures << "#{relative_path} missing #{needle.inspect}" unless body.include?(needle)
  end
end

worker = File.join(MASTER, "bin", "tts-worker")
failures << "MASTER/bin/tts-worker must be executable" unless File.executable?(worker)

if ENV["MASTER_TTS_REQUIRE_HOST_BACKEND"] == "1"
  host_backend = system("command", "-v", "edge-tts", out: File::NULL, err: File::NULL) ||
    system("command", "-v", "espeak", out: File::NULL, err: File::NULL) ||
    File.executable?("/usr/local/bin/espeak") ||
    File.executable?("/usr/bin/espeak")
  failures << "host missing edge-tts/espeak backend" unless host_backend
end

if failures.any?
  warn "MASTER TTS gate failures:"
  failures.each { |failure| warn "  - #{failure}" }
  exit 1
end

puts "MASTER TTS gate passed."
