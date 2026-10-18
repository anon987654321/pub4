# frozen_string_literal: true

require "ipaddr"
require "resolv"
require "time"
require "fileutils"
require_relative "exec"
require_relative "ssrf_guard"

module Master
  module Io
    # Bounded active assessment of one explicitly authorized host. No shell, CIDR,
    # full-port sweep, brute force or exploit scripts.
    class Nmap
      NAME = "nmap".freeze
      TIER = :dangerous
      DESCRIPTION = "Bounded Nmap assessment for one authorized hostname or IP.".freeze
      TIMEOUT = 180
      PROFILES = %w[basic services safe].freeze
      HOSTNAME_RE = /\A(?=.{1,253}\z)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)*[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z/i.freeze

      def initialize(governor:, root: Master::ROOT, event_bus: nil, timeout_s: TIMEOUT)
        @governor = governor
        @root = File.expand_path(root)
        @bus = event_bus
        @timeout_s = timeout_s
      end

      def call(target:, profile: "basic", authorized: false, allow_private: false)
        target = target.to_s.strip
        profile = profile.to_s
        return Result.err("nmap: authorized=true is required for active scanning", category: :policy) unless authorized == true
        return Result.err("nmap: profile must be basic, services, or safe", category: :validation) unless PROFILES.include?(profile)
        return Result.err("nmap: target is required", category: :validation) if target.empty?

        resolved = resolve_target(target, allow_private: allow_private == true)
        return resolved if resolved.is_a?(Master::Result)
        scan_ip, family = resolved

        permit = @governor.permit?(NAME, TIER, { target:, scan_ip:, profile:, authorized: true, allow_private: allow_private == true })
        return permit if permit.err?
        executable = Exec.which("nmap")
        return Result.err("nmap: executable unavailable; install it separately on the authorized scanner host", category: :infrastructure) unless executable

        argv = [executable, "-n", "-Pn", "-sT", "-T2", "--top-ports", "100",
                "--max-retries", "1", "--host-timeout", "120s", "--max-rate", "100"]
        argv << "-6" if family == 6
        argv.concat(["-sV", "--version-light"]) if %w[services safe].include?(profile)
        argv.concat(["--script", "safe"]) if profile == "safe"
        argv.concat(["-oN", "-", scan_ip])

        @bus&.publish("tool:before", tool: NAME, target:, scan_ip:, profile:)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        out, err, status = Exec.capture3(*argv, timeout: @timeout_s)
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
        report = [
          "MASTER Nmap assessment",
          "Requested target: #{target}",
          "Scanned address: #{scan_ip}",
          "Profile: #{profile}",
          "Authorization: authorized=true flag supplied; dangerous-tier governor permit granted; target ownership is not independently verified",
          "Limits: one resolved address; TCP top 100 ports; T2; one retry; 120-second host timeout; #{@timeout_s}-second process timeout",
          "Started: #{Time.now.utc.iso8601}",
          "Elapsed seconds: #{elapsed.round(2)}",
          "Exit: #{status.success? ? 'success' : "failure (#{status.exitstatus || status.termsig})"}",
          "", "Nmap output", out.to_s.byteslice(0, 24_000).to_s,
          "", "Stderr", err.to_s.byteslice(0, 3_000).to_s
        ].join("\n")
        saved = write_report(target, report)
        return saved if saved.is_a?(Master::Result) && saved.err?

        @bus&.publish("tool:after", tool: NAME, target:, profile:, success: status.success?, report_path: saved)
        return Result.err("nmap: scan failed (exit #{status.exitstatus || status.termsig}); report: #{saved}\n#{err.to_s.byteslice(0, 500)}", category: :infrastructure) unless status.success?

        Result.ok("#{report}\n\nSaved report: #{saved}")
      rescue StandardError => e
        Result.err("nmap: #{e.class}: #{e.message}", category: :infrastructure)
      end

      private

      def resolve_target(target, allow_private:)
        return Result.err("nmap: URLs, CIDR, ranges, wildcards and ports are not valid targets", category: :validation) if target.match?(%r{://}) || target.include?("/") || target.include?("*") || target.include?("@")

        candidate = target.delete_prefix("[").delete_suffix("]")
        ip = begin
          IPAddr.new(candidate)
        rescue IPAddr::InvalidAddressError
          nil
        end
        if ip
          if Master::Io::SsrfGuard.blocked_ip?(ip) && !allow_private
            return Result.err("nmap: private, loopback, link-local, multicast or reserved address needs allow_private=true", category: :policy)
          end
          return [ip.to_s, ip.ipv4? ? 4 : 6]
        end

        return Result.err("nmap: colon is only valid in an IP literal; ports are not accepted", category: :validation) if target.include?(":")
        return Result.err("nmap: invalid hostname", category: :validation) unless HOSTNAME_RE.match?(target)
        if (target == "localhost" || target.end_with?(".local", ".localhost", ".internal")) && !allow_private
          return Result.err("nmap: local-only hostnames need allow_private=true", category: :policy)
        end

        addresses = Resolv.getaddresses(target).uniq
        return Result.err("nmap: DNS returned no addresses", category: :infrastructure) if addresses.empty?
        return Result.err("nmap: DNS returned too many addresses (maximum 8)", category: :validation) if addresses.size > 8
        parsed = addresses.map { |address| IPAddr.new(address) }
        if !allow_private && parsed.any? { |address| Master::Io::SsrfGuard.blocked_ip?(address) }
          return Result.err("nmap: DNS includes a private or reserved address; refusing ambiguous scope", category: :policy)
        end
        chosen = parsed.first
        [chosen.to_s, chosen.ipv4? ? 4 : 6]
      rescue StandardError => e
        Result.err("nmap: target validation or DNS failed: #{e.class}: #{e.message}", category: :validation)
      end

      def write_report(target, content)
        root = File.realpath(@root)
        state_dir = File.join(root, ".master")
        return Result.err("nmap: refusing symlinked .master directory", category: :policy) if File.symlink?(state_dir)

        FileUtils.mkdir_p(state_dir, mode: 0o700)
        report_dir = File.join(state_dir, "security_assessments")
        return Result.err("nmap: refusing symlinked report directory", category: :policy) if File.symlink?(report_dir)

        FileUtils.mkdir_p(report_dir, mode: 0o700)
        real_dir = File.realpath(report_dir)
        return Result.err("nmap: report directory escapes checkout", category: :policy) unless real_dir.start_with?(root + File::SEPARATOR)

        slug = target.downcase.gsub(/[^a-z0-9.-]+/, "-").gsub(/\A-+|-+\z/, "")[0, 80]
        path = File.join(real_dir, "nmap_#{slug.empty? ? 'target' : slug}_#{Time.now.utc.strftime('%Y%m%dT%H%M%S')}.txt")
        File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |file| file.write(content) }
        path
      rescue StandardError => e
        Result.err("nmap: unable to save report: #{e.class}: #{e.message}", category: :infrastructure)
      end
    end
  end
end
