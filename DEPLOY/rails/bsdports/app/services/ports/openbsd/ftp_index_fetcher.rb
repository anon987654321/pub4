# frozen_string_literal: true

require "net/ftp"
require "pathname"
require "tempfile"

module Ports
  module Openbsd
    class FtpIndexFetcher
      DEFAULT_HOST = "ftp.openbsd.org"

      def initialize(platform:, host: DEFAULT_HOST)
        @platform = platform
        @host = host
        @base_path = platform.mirror_url.to_s.sub(%r{\Aftp://[^/]+}, "")
      end

      def fetch_category_index(category)
        Tempfile.create([ "bsdports-index-#{category}-", ".txt" ]) do |tmp|
          Net::FTP.open(@host, read_timeout: 30, open_timeout: 15) do |ftp|
            ftp.passive = true
            remote = File.join(@base_path, "ports", category, "INDEX")
            ftp.gettextfile(remote, tmp.path)
          end
          Pathname.new(tmp.path)
        end
      rescue StandardError => e
        Rails.logger.warn("bsdports ftp index fetch failed category=#{category} error=#{e.message}")
        nil
      end
    end
  end
end