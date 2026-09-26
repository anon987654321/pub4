# frozen_string_literal: true

require "json"
require "fileutils"
require "securerandom"
require "tempfile"

module Master
  module Device
    # Tiny cross-process handoff from the resident Android wake service to the
    # already-open web face. The file is an event register, not a queue: a
    # connected face consumes events newer than its own stream start time.
    class WakeSignal
      PATH = ".master/wake_event.json"
      VERSION = 1

      def self.publish(root:, phrase:, at: Time.now.to_f)
        path = File.join(root, PATH)
        FileUtils.mkdir_p(File.dirname(path))
        payload = {
          version: VERSION,
          id: SecureRandom.hex(12),
          type: "device:wake",
          phrase: phrase.to_s,
          at: at.to_f,
        }
        Tempfile.create(["wake-event-", ".json"], File.dirname(path)) do |tmp|
          tmp.write(JSON.generate(payload))
          tmp.flush
          tmp.close
          File.rename(tmp.path, path)
        end
        payload
      end

      def self.read(root:)
        path = File.join(root, PATH)
        JSON.parse(File.read(path, encoding: "UTF-8"), symbolize_names: true)
      rescue Errno::ENOENT, JSON::ParserError
        nil
      end
    end
  end
end
