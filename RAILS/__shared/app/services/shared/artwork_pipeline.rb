# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open-uri"
require_relative "../../../../contracts/studio"
require "tmpdir"
require "time"

module Shared
  # One publication boundary for generated stills. A provider URL is never the
  # published asset: it is downloaded, graded, atomically moved, and recorded.
  class ArtworkPipeline
    VERSION = "v2"
    LEDGER_DIR = "artwork"
    GRADE_PRESET = ENV.fetch("ARTWORK_POSTPRO_PRESET", "magic_hour")
    GRADE_STOCK = ENV.fetch("ARTWORK_POSTPRO_STOCK", "kodak_portra")

    class << self
      def seed(surface:, city:, brief: "")
        digest = Digest::SHA256.hexdigest([VERSION, surface, city, brief].join("\0"))
        digest[0, 8].to_i(16) % 2_147_483_646
      end

      def publish_remote(url:, destination:, surface:, city:, brief:, source:)
        raise ArgumentError, "artwork source must be http(s)" unless url.to_s.match?(%r{\Ahttps?://})
        raise "postpro is required before publishing generated artwork" unless postpro_script

        FileUtils.mkdir_p(File.dirname(destination))
        seed_value = seed(surface:, city:, brief:)
        Dir.mktmpdir("pub4-artwork") do |dir|
          input = File.join(dir, "source.webp")
          graded = File.join(dir, "graded.jpg")
          URI.open(url, "rb", read_timeout: 60) do |remote|
            File.binwrite(input, remote.read)
          end
          grade!(input:, output: graded)
          raise "postpro produced no output" unless File.file?(graded) && File.size(graded).positive?

          temporary = "#{destination}.tmp-#{Process.pid}-#{Thread.current.object_id}"
          FileUtils.cp(graded, temporary)
          File.rename(temporary, destination)
        end

        record!(
          surface:, city:, brief:, seed: seed_value, source:,
          destination:, model: ENV["NEWSLETTER_REPLICATE_MODEL"],
        )
        destination
      end

      def record!(surface:, city:, brief:, seed:, source:, destination:, model:)
        path = ledger_path
        FileUtils.mkdir_p(File.dirname(path))
        entry = {
          version: VERSION,
          at: Time.now.utc.iso8601,
          surface:,
          city:,
          brief:,
          seed:,
          source:,
          model: model.to_s.empty? ? nil : model,
          sha256: Digest::SHA256.file(destination).hexdigest,
          artifact: destination,
        }
        File.open(path, File::WRONLY | File::CREAT | File::APPEND, 0o640) do |file|
          file.flock(File::LOCK_EX)
          file.write(JSON.generate(entry) + "\n")
        end
        entry
      end

      def postpro_script
        Contracts::Studio.postpro_script&.to_s
      end

      def ledger_path
        configured = ENV["ARTWORK_SEED_LEDGER"].to_s
        return File.expand_path(configured) unless configured.empty?

        Rails.root.join("storage", LEDGER_DIR, "seed-ledger.jsonl")
      end

      private

      def grade!(input:, output:)
        ok = system(
          RbConfig.ruby, postpro_script,
          "--input", input, "--output", output,
          "--preset", GRADE_PRESET,
          out: File::NULL, err: File::NULL,
        )
        raise "postpro grading failed" unless ok
      end
    end
  end
end
