# frozen_string_literal: true

require "net/http"
require "uri"
require "tmpdir"
require "open3"

module Ports
  module Openbsd
    # Downloads and extracts <mirror>/<release>/ports.tar.gz so the existing
    # Makefile walk can read real metadata — category, COMMENT, maintainer,
    # dependencies — which the published package index does not carry.
    #
    # Guarded on free disk, and the guard is the point. Measured 2026-08-05 the
    # tarball is 56 MB compressed and expands to several hundred MB, while vm23
    # has 962 MB free on /home at 95% full — TODO.md,
    # home_partition_full_from_git_history. Running this there
    # unguarded would fill the disk that already blocks a deploy. When there is
    # not enough room it declines and says so; the package-index path still
    # gives a browsable catalogue.
    class PortsTarball
      DEFAULT_BASE = "https://cdn.openbsd.org/pub/OpenBSD"
      # 56 MB download + extraction + slack. Deliberately generous: the failure
      # mode being avoided is a full disk on the deploy host.
      REQUIRED_FREE_BYTES = 2 * 1024 * 1024 * 1024
      OPEN_TIMEOUT = 15
      READ_TIMEOUT = 300

      def self.enabled? = ENV["BSDPORTS_PORTS_TARBALL"] == "1"

      def initialize(platform:, release: nil, base: nil, workdir: nil)
        @platform = platform
        @base = (base || ENV["BSDPORTS_MIRROR"] || DEFAULT_BASE).chomp("/")
        @release = release
        @workdir = workdir
      end

      attr_reader :platform, :base, :release

      def url = "#{base}/#{release}/ports.tar.gz"

      # Yields the extracted ports root, or returns nil with a logged reason.
      def with_tree
        reason = decline_reason
        if reason
          Rails.logger.info("bsdports ports.tar.gz skipped: #{reason}")
          return nil
        end

        Dir.mktmpdir("bsdports-ports-", @workdir) do |dir|
          tarball = File.join(dir, "ports.tar.gz")
          return nil unless download(url, tarball)

          out, status = Open3.capture2e("tar", "xzf", tarball, "-C", dir)
          unless status.success?
            Rails.logger.warn("bsdports ports.tar.gz extract failed: #{out.lines.last(3).join.strip}")
            return nil
          end
          File.delete(tarball) if File.file?(tarball)

          root = Pathname.new(File.join(dir, "ports"))
          return yield(root) if root.directory?

          Rails.logger.warn("bsdports ports.tar.gz extracted without a ports/ root")
          nil
        end
      end

      # Nil when the tarball path may run; a human-readable reason otherwise.
      def decline_reason
        return "BSDPORTS_PORTS_TARBALL is not 1" unless self.class.enabled?
        return "release unknown" if release.blank?

        free = free_bytes(@workdir || Dir.tmpdir)
        return nil if free.nil? # cannot measure — do not block on that alone
        return nil if free >= REQUIRED_FREE_BYTES

        "needs #{REQUIRED_FREE_BYTES / 1024 / 1024} MB free, has #{free / 1024 / 1024} MB"
      end

      private

      def free_bytes(path)
        out, status = Open3.capture2e("df", "-k", path)
        return nil unless status.success?

        line = out.lines[1] or return nil
        available_kb = line.split[3].to_i
        available_kb.positive? ? available_kb * 1024 : nil
      rescue StandardError # scan: intentional — an unreadable df line means unknown space; the caller treats unknown as insufficient
        nil
      end

      def download(from, to, limit: 3)
        raise "too many redirects for #{from}" if limit.zero?

        uri = URI.parse(from)
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                            open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
          http.request(Net::HTTP::Get.new(uri)) do |response|
            case response
            when Net::HTTPSuccess
              File.open(to, "wb") { |f| response.read_body { |chunk| f.write(chunk) } }
              return true
            when Net::HTTPRedirection
              return download(URI.join(from, response["location"]).to_s, to, limit: limit - 1)
            else
              Rails.logger.warn("bsdports ports.tar.gz #{from} returned #{response.code}")
              return false
            end
          end
        end
        false
      rescue StandardError => e
        Rails.logger.warn("bsdports ports.tar.gz download failed: #{e.class}: #{e.message}")
        false
      end
    end
  end
end
