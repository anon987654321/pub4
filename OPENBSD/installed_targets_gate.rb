#!/usr/bin/env ruby
# frozen_string_literal: true

# Every executable the box is told to run must be one the repo actually installs.
#
# On 2026-08-25 /etc/daily.local guarded a root-run drift check on
# `[ -x /usr/local/bin/config_drift_gate.rb ]`. Nothing installed that file:
# install_root_configs copies etc/, usr/ and var/ from the repo, and the script
# lives at OPENBSD/config_drift_gate.rb, outside usr/local/bin/. So the guard was
# false on every run and the check had never executed. Live had been hand-edited
# to run it out of /home/dev/pub4 instead — root executing a file the dev user
# can rewrite, every morning.
#
# Both halves of that were invisible for the same reason: a guard, its target,
# and the thing that installs the target are three separate facts, and nothing
# compared them. This compares them, from the repo, with no box required — which
# is the point. A check that only runs on vm23 cannot fail a pull request.
#
# It reads the config the way the box does: crontab, the periodic scripts and
# every rc.d service, pulls out each /usr/local/bin path they name, and asks
# whether the repo provides it — either as a tracked file under
# OPENBSD/usr/local/bin/ (install_root_configs copies the tree) or through an
# explicit `install` line in OPERATOR.sh.
#
#   ruby OPENBSD/installed_targets_gate.rb
#   ruby OPENBSD/installed_targets_gate.rb --json

require "json"

module Deploy
  module InstalledTargetsGate
    OPENBSD = File.expand_path(__dir__)
    SHIPPED_DIR = File.join(OPENBSD, "usr", "local", "bin")

    CONFIG_GLOBS = ["etc/crontab*", "etc/*.local", "etc/rc.d/*"].freeze

    # Base-system and package binaries. The gate is about what THIS repo is
    # responsible for installing, not about auditing the OpenBSD ports tree.
    PROVIDED_BY_PACKAGES = %w[
      ruby34 bundle34 git sqlite3 psql rcctl relayctl nsd-control acme-client
      vips ffmpeg node npm doas su tee logger newsyslog drill dig sendmail curl wget
    ].freeze

    module_function

    def config_files
      CONFIG_GLOBS.flat_map { |glob| Dir.glob(File.join(OPENBSD, glob)) }.select { |f| File.file?(f) }.sort
    end

    # Every /usr/local/bin/<name> the config names, with the file that named it.
    def referenced
      config_files.each_with_object({}) do |path, acc|
        File.read(path, encoding: "UTF-8").scrub.scan(%r{/usr/local/bin/([A-Za-z0-9_.-]+)}) do |(name)|
          name = name.sub(/\.\z/, "") # prose punctuation, not part of the filename
          next if PROVIDED_BY_PACKAGES.include?(name)

          (acc[name] ||= []) << path.sub("#{OPENBSD}/", "")
        end
      end
    end

    def shipped
      Dir.glob(File.join(SHIPPED_DIR, "*")).map { |f| File.basename(f) }
    end

    def explicitly_installed
      operator = File.join(OPENBSD, "OPERATOR.sh")
      return [] unless File.file?(operator)

      File.read(operator, encoding: "UTF-8").scrub
          .scan(%r{install\s[^\n]*?/usr/local/bin/([A-Za-z0-9_.-]+)}).flatten
    end

    def provided
      (shipped + explicitly_installed).uniq
    end

    def orphans
      have = provided
      referenced.reject { |name, _| have.include?(name) }
    end

    def run(json: false)
      missing = orphans
      if json
        puts JSON.generate(referenced: referenced.size, provided: provided.size,
                           missing: missing.map { |n, where| { target: n, referenced_by: where } })
        return missing.empty?
      end

      puts "installed-targets: #{referenced.size} /usr/local/bin target(s) named by config, " \
           "#{provided.size} provided by the repo"
      if missing.empty?
        puts "installed-targets: clean — every target the box is told to run is one the repo installs"
        return true
      end

      missing.each do |name, where|
        warn "installed-targets: /usr/local/bin/#{name} is named by #{where.join(', ')} and nothing installs it"
      end
      warn "installed-targets: add it to OPENBSD/usr/local/bin/ (copied wholesale) or an install line in OPERATOR.sh"
      warn "installed-targets: a guard on a target that does not exist fails OPEN, into silence"
      false
    end
  end
end

if $PROGRAM_NAME == __FILE__
  ok = Deploy::InstalledTargetsGate.run(json: ARGV.include?("--json"))
  exit(ok ? 0 : 1)
end
