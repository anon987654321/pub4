# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require_relative "../../trace/dmesg"

module Master
  module Fix
    module Scan
      # Which files a model has already read clean. A semantic read is one model call per file per law,
      # so repeating it on a file that has not changed since a clean verdict buys nothing. The key is the
      # file's content and the semantic law set, so editing the file or the laws asks the question again.
      # An inconclusive read is never recorded: a model outage must not look like a clean file.
      class SemanticVerdicts
        FILE = File.join(".master", "semantic_clean.json")

        def initialize(root: Master::ROOT)
          @path = File.join(root, FILE)
          @mutex = Mutex.new
          @seen = load_seen
        end

        def clean?(relative, code:, laws:)
          @mutex.synchronize { @seen[relative] == digest(code:, laws:) }
        end

        def record(relative, code:, laws:)
          @mutex.synchronize do
            @seen[relative] = digest(code:, laws:)
            persist
          end
        end

        private

        def digest(code:, laws:)
          ids = laws.map { |law| law.id.to_s }.sort
          Digest::SHA256.hexdigest("#{Digest::SHA256.hexdigest(code)}\n#{ids.join(",")}")
        end

        def load_seen
          return {} unless File.exist?(@path)

          JSON.parse(File.read(@path, encoding: "UTF-8"))
        rescue JSON::ParserError => e
          Master::Trace::Dmesg.status("scan0", "semantic verdicts unreadable, starting empty: #{e.message[0, 80]}")
          {}
        end

        def persist
          FileUtils.mkdir_p(File.dirname(@path))
          temp = "#{@path}.#{Process.pid}"

          File.write(temp, JSON.generate(@seen))
          File.rename(temp, @path)
        end
      end
    end
  end
end
