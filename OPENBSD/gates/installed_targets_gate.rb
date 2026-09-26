#!/usr/bin/env ruby
# frozen_string_literal: true

# Every executable the box is told to run must be one the repo actually installs.
#
# On 2026-08-25 /etc/daily.local guarded a root-run drift check on
# `[ -x /usr/local/bin/config_drift_gate.rb ]`. Nothing installed that file:
# install_root_configs copies etc/, usr/ and var/ from the repo, and the script
# lives at OPENBSD/gates/config_drift_gate.rb, outside usr/local/bin/. So the guard was
# false on every run and the check had never executed. Live had been hand-edited
# to run it out of /home/dev/pub4 instead — root executing a file the dev user
# can rewrite, every morning.
#
# Both halves of that were invisible for the same reason: a guard, its target,
# and the thing that installs the target are three separate facts, and nothing
# compared them. This compares them, from the repo, with no box required — which
# is the point. A check that only runs on vm23 cannot fail a pull request.
#
# It reads what the box runs: crontab, the periodic scripts, every rc.d service,
# and every script the repo itself installs under /usr/local — resource_guard.sh
# calls its crisis tier at /usr/local/bin/emergency_cpu.sh and dot-sources
# /usr/local/libexec/stale_ci_cleanup.ksh, and a script is as much a referrer as
# a crontab line. It pulls out each /usr/local/{bin,libexec} path they name and
# asks whether the repo provides it — either as a tracked file under
# OPENBSD/usr/local/ (install_root_configs copies the tree) or through an
# explicit `install` line in OPERATOR.sh.
#
#   ruby OPENBSD/gates/installed_targets_gate.rb
#   ruby OPENBSD/gates/installed_targets_gate.rb --json

require "json"
require_relative "../lib/operator_source"

module Deploy
  module InstalledTargetsGate
    DEFAULT_ROOT = File.expand_path("..", __dir__)

    # Overridable so a test can plant a tree and watch the gate fail on it.
    @root = DEFAULT_ROOT
    class << self
      attr_accessor :root
    end

    CONFIG_GLOBS = ["etc/crontab*", "etc/*.local", "etc/rc.d/*"].freeze
    SHIPPED_GLOB = "usr/local/{bin,libexec}/*"
    # A name that runs on into a slash is a directory named in prose — the
    # /usr/local/bin/lib/ that config_drift_gate.rb explains away — not a target.
    TARGET = %r{/usr/local/(bin|libexec)/([A-Za-z0-9_.-]+)(?![A-Za-z0-9_./-])}
    INSTALL_LINE = %r{install\s[^\n]*?/usr/local/(bin|libexec)/([A-Za-z0-9_.-]+)}
    INSTALL_SOURCE = %r{install\s[^\n]*?"\$\{SCRIPT_DIR\}/([A-Za-z0-9_./-]+)"}

    # Base-system and package binaries. The gate is about what THIS repo is
    # responsible for installing, not about auditing the OpenBSD ports tree.
    PROVIDED_BY_PACKAGES = %w[
      ruby34 bundle34 git sqlite3 psql rcctl relayctl nsd-control acme-client
      vips ffmpeg node npm doas su tee logger newsyslog drill dig sendmail curl wget
    ].freeze

    module_function

    def read(path) = File.read(path, encoding: "UTF-8").scrub

    def operator
      path = File.join(root, "OPERATOR.sh")
      File.file?(path) ? OperatorSource.read(path) : ""
    end

    # The config that names a path, and every script the repo puts under
    # /usr/local — including the ones OPERATOR.sh installs from the tree root.
    def referrers
      config = CONFIG_GLOBS.flat_map { |glob| Dir.glob(File.join(root, glob)) }
      installed = operator.scan(INSTALL_SOURCE).flatten.map { |name| File.join(root, name) }
      (config + Dir.glob(File.join(root, SHIPPED_GLOB)) + installed).select { |f| File.file?(f) }.uniq.sort
    end

    # Every /usr/local/{bin,libexec}/<name> a referrer names, keyed "bin/<name>",
    # with the files that named it.
    def referenced
      referrers.each_with_object({}) do |path, acc|
        read(path).scan(TARGET) do |dir, name|
          name = name.sub(/\.\z/, "") # prose punctuation, not part of the filename
          next if PROVIDED_BY_PACKAGES.include?(name)

          (acc["#{dir}/#{name}"] ||= []) << path.delete_prefix("#{root}/")
        end
      end
    end

    def shipped
      Dir.glob(File.join(root, SHIPPED_GLOB)).map { |f| f.delete_prefix("#{root}/usr/local/") }
    end

    def explicitly_installed
      operator.scan(INSTALL_LINE).map { |dir, name| "#{dir}/#{name}" }
    end

    def provided
      (shipped + explicitly_installed).uniq
    end

    def orphans
      have = provided
      referenced.reject { |target, _| have.include?(target) }
    end

    def run(json: false)
      missing = orphans
      if json
        puts JSON.generate(referenced: referenced.size, provided: provided.size,
                           missing: missing.map { |target, where| { target: target, referenced_by: where } })
        return missing.empty?
      end

      puts "installed-targets: #{referenced.size} /usr/local target(s) named by config and installed scripts, " \
           "#{provided.size} provided by the repo"
      if missing.empty?
        puts "installed-targets: clean — every target the box is told to run is one the repo installs"
        return true
      end

      missing.each do |target, where|
        warn "installed-targets: /usr/local/#{target} is named by #{where.join(', ')} and nothing installs it"
      end
      warn "installed-targets: add it to OPENBSD/usr/local/ (copied wholesale) or an install line in OPERATOR.sh"
      warn "installed-targets: a guard on a target that does not exist fails OPEN, into silence"
      false
    end
  end
end

if $PROGRAM_NAME == __FILE__
  ok = Deploy::InstalledTargetsGate.run(json: ARGV.include?("--json"))
  exit(ok ? 0 : 1)
end
