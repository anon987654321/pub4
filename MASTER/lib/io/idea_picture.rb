# frozen_string_literal: true

require "json"
require "open3"
require "rbconfig"

module Master
  module Io
    # MASTER-facing adapter for STUDIO photograph generation. MASTER owns the
    # request and the result contract; STUDIO owns provider calls, grading and
    # media creation.
    class IdeaPicture
      ROOT = File.expand_path("../../../STUDIO/photograph.rb", __dir__)

      def initialize(script: ROOT)
        @script = script
      end

      def write(words, film: true, duration: 5)
        raise "STUDIO photograph entrypoint is unavailable" unless File.file?(@script)

        argv = [RbConfig.ruby, @script]
        argv << "--film" if film
        argv << "--duration" << duration.to_i.to_s
        argv << words.to_s
        stdout, status = Open3.capture2e(*argv, chdir: File.dirname(@script))
        raise "STUDIO photograph failed: #{stdout.lines.last.to_s.strip}" unless status.success?

        JSON.parse(stdout).transform_keys(&:to_sym)
      end
    end
  end
end
