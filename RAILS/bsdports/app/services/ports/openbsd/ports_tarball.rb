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
    # has 962 MB free on /home at 95% full — the old backlog,
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
      MAX_TARBALL_BYTES = 150 * 1024 * 1024
      MAX_SIGNATURE_BYTES = 64 * 1024

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
          signature = File.join(dir, "SHA256.sig")
          return nil unless download("#{base}/#{release}/SHA256.sig", signature, max_bytes: MAX_SIGNATURE_BYTES)
          return nil unless download(url, tarball, max_bytes: MAX_TARBALL_BYTES)
          return nil unless verify_tarball(tarball, signature)

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
        return "invalid release identifier" unless release.to_s.match?(/\A\d+\.\d+\z/)
        return "trusted signify key or signify executable unavailable" unless verification_ready?

        free = free_bytes(@workdir || Dir.tmpdir)
        return "free disk space unknown" if free.nil?
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
      rescue StandardError # An unreadable df line means unknown space; decline_reason fails closed.
        nil
      end


      def trusted_signify_key
        configured = ENV["BSDPORTS_SIGNIFY_KEY"].to_s
        return File.file?(configured) ? configured : nil if configured.present?

        candidate = "/etc/signify/openbsd-#{release.to_s.delete('.')}-base.pub"
        File.file?(candidate) ? candidate : nil
      end

      def verification_ready?
        trusted_signify_key.present? &&
          ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |directory|
            File.executable?(File.join(directory, "signify"))
          end
      end

      def verify_tarball(archive, signature)
        key = trusted_signify_key
        return false unless key && verification_ready?

        output, status = Open3.capture2e(
          "signify", "-C", "-p", key, "-x", File.basename(signature), File.basename(archive),
          chdir: File.dirname(archive)
        )
        return true if status.success?

        Rails.logger.warn("bsdports ports.tar.gz signature verification failed: #{output.lines.last(3).join.strip}")
        false
      rescue StandardError => e
        Rails.logger.warn("bsdports ports.tar.gz verification failed: #{e.class}: #{e.message}")
        false
      end

      def download(from, to, limit: 3, origin: nil, max_bytes: MAX_TARBALL_BYTES)
        raise "too many redirects for #{from}" if limit.negative?

        uri = URI.parse(from)
        unless uri.is_a?(URI::HTTPS) && uri.port == 443 && uri.userinfo.nil?
          raise URI::InvalidURIError, "ports mirror must use HTTPS on port 443"
        end
        origin ||= [ uri.scheme, uri.host, uri.port ]
        unless [ uri.scheme, uri.host, uri.port ] == origin
          raise URI::InvalidURIError, "ports mirror redirect changed origin"
        end

        # Resolve, reject private/reserved addresses, pin the socket destination,
        # and cap the body before writing it. Never follow a redirect to a new host.
        response = Shared::OutboundHttp.request(
          uri, max_body: max_bytes, open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT
        )
        if response.is_a?(Net::HTTPRedirection)
          target = URI.join(from, response["location"].to_s)
          return download(target.to_s, to, limit: limit - 1, origin:, max_bytes:)
        end
        unless response.is_a?(Net::HTTPSuccess)
          Rails.logger.warn("bsdports ports.tar.gz #{from} returned #{response.code}")
          return false
        end

        File.open(to, "wb") { |file| file.write(response.body) }
        true
      rescue Shared::OutboundHttp::BodyTooLarge => e
        Rails.logger.warn("bsdports ports.tar.gz rejected: #{e.message}")
        false
      rescue StandardError => e
        Rails.logger.warn("bsdports ports.tar.gz download failed: #{e.class}: #{e.message}")
        false
      end
    end
  end
end
