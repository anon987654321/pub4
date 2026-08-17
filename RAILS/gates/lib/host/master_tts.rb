# frozen_string_literal: true

require_relative "../../../../OPENBSD/lib/gate_result"

module Deploy
  class MasterTtsGate
    ROOT = File.expand_path("../../../..", __dir__)
    MASTER = File.join(ROOT, "MASTER")

    CHECKS = {
      "MASTER/lib/voice/speech.rb" => [
        "def edge_tts_available?",
        "def espeak_path",
        "synthesize_espeak(text_str) if espeak_path",
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
        "tts-e2e poll",
        "tts-e2e"
      ],
      "OPENBSD/OPERATOR.sh" => [
        "espeak"
      ],
      "OPENBSD/etc/rc.d/master" => [
        "Master::Voice::TtsSupervisor.ensure_daemon!",
        "MASTER_TTS_TIMEOUT=45"
      ],
    }.freeze

    def self.run
      result = GateResult.new

      CHECKS.each do |relative_path, needles|
        path = File.join(ROOT, relative_path)
        unless File.file?(path)
          result.fail("missing #{relative_path}")
          next
        end

        body = File.read(path)
        needles.each do |needle|
          result.fail("#{relative_path} missing #{needle.inspect}") unless body.include?(needle)
        end
      end

      worker = File.join(MASTER, "bin", "tts-worker")
      result.fail("MASTER/bin/tts-worker must be executable") unless File.executable?(worker)

      if ENV["MASTER_TTS_REQUIRE_HOST_BACKEND"] == "1"
        host_backend = system("command", "-v", "edge-tts", out: File::NULL, err: File::NULL) ||
          system("command", "-v", "espeak", out: File::NULL, err: File::NULL) ||
          File.executable?("/usr/local/bin/espeak") ||
          File.executable?("/usr/bin/espeak")
        result.fail("host missing edge-tts/espeak backend") unless host_backend
      end

      result
    end
  end
end
