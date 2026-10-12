# frozen_string_literal: true

require "fileutils"
require_relative "../transport"

module Master
  module Io
    module Chat
      class Slskd < Transport
        # What may be downloaded and where it may land. MASTER only decides the
        # yes or no and prepares the directory; slskd does the transfer, and
        # nothing here opens, plays, indexes or executes what arrives.
        class Quarantine
          class Refused < StandardError; end

          EXTENSIONS = %w[wav flac aiff mp3 ogg m4a opus].freeze
          DEFAULT_MAX_MB = 300
          REPO_ROOT = File.expand_path("../../../../..", __dir__)
          NOTICE = "slsk0: Soulseek is widely used for unlicensed music; you are responsible " \
                   "for having the right to download each file"

          attr_reader :dir, :max_bytes

          def initialize(env: ENV)
            @dir = File.expand_path(env["MASTER_SLSK_DIR"] || File.join(Dir.home, ".master/slsk/incoming"))
            @max_bytes = (Float(env["MASTER_SLSK_MAX_MB"] || DEFAULT_MAX_MB) * 1024 * 1024).to_i
          rescue ArgumentError
            raise Refused, "MASTER_SLSK_MAX_MB is not a number"
          end

          # Raises Refused with the reason, else returns the basename to expect.
          def vet!(filename, size)
            base = File.basename(filename.to_s.tr("\\", "/"))
            ext = File.extname(base).delete_prefix(".").downcase
            raise Refused, "extension .#{ext} not allowed (#{EXTENSIONS.join(" ")})" unless EXTENSIONS.include?(ext)
            raise Refused, "size unknown" unless size.is_a?(Integer) && size.positive?
            raise Refused, "#{mb(size)} MB is over the #{mb(max_bytes)} MB cap" if size > max_bytes

            base
          end

          # Created 0700 and never inside the repository.
          def prepare!
            real = File.expand_path(dir)
            raise Refused, "quarantine #{real} is inside the repository" if real == REPO_ROOT || real.start_with?("#{REPO_ROOT}/")

            FileUtils.mkdir_p(real, mode: 0o700)
            File.chmod(0o700, real)
            real
          end

          # True the first time only, so the notice is shown once per machine.
          def first_notice?
            marker = File.join(File.dirname(dir), ".notice")
            return false if File.exist?(marker)

            FileUtils.mkdir_p(File.dirname(marker), mode: 0o700)
            File.write(marker, "shown\n")
            true
          rescue SystemCallError
            false
          end

          private

          def mb(bytes) = (bytes / 1024.0 / 1024).round(1)
        end
      end
    end
  end
end
