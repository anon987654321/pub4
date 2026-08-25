# frozen_string_literal: true

# Does every declaration on this box reach something that runs it?
#
# OPENBSD is the tree where a declaration and its reader live in different
# files by design: crontab.vm23 names a path, OPERATOR.sh installs it, rc.d
# holds the service, nsd.conf names the zone. Nothing in the tree fails when
# those halves stop agreeing, and the failure is invisible from either side —
# both files are complete and correct, and the job is not scheduled.
#
# That has happened. test/test_tracked_crontab.rb records uptime-check.sh sitting
# in crontab.vm23 and usr/local/bin/ for six days while being on neither the
# box's crontab nor its filesystem, because the merge loop skipped the line
# correctly and silently.
#
#   ruby OPENBSD/tools/reach.rb
#   ruby OPENBSD/tools/reach.rb --json
#
# Three questions, each about the tree rather than the box. Box state is
# health_check.rb's job; this is what a fresh OPERATOR.sh run would produce.

require "json"
require_relative "../lib/utf8"

module Pub4
  module OpenbsdReach
    DEFAULT_ROOT = File.expand_path("..", __dir__)

    # Overridable so the checks can be shown to fire. A probe nobody has watched
    # fail is the same shape as the drift it is looking for.
    @root = DEFAULT_ROOT
    class << self
      attr_accessor :root
    end

    Finding = Struct.new(:check, :subject, :detail, keyword_init: true)

    module_function

    def read(*parts)
      path = File.join(root, *parts)
      File.file?(path) ? File.read(path, encoding: "UTF-8") : ""
    end

    # --- cron ----------------------------------------------------------------

    # A cron line is five time fields then a command. The command reaches
    # something if the tree tracks it at the path it names, or if OPERATOR.sh
    # installs it there from somewhere else — resource_guard.sh is tracked at the
    # OPENBSD root and installed into /usr/local/bin, which reads as missing to
    # anything that only checks the path.
    def cron_commands
      read("etc", "crontab.vm23").lines
        .grep(/\A[\d*]/)
        .filter_map { |line| line.split(/\s+/, 6).last.to_s[/\A\S+/] }
        .uniq
    end

    def cron_findings
      operator = read("OPERATOR.sh")
      cron_commands.filter_map do |cmd|
        next if File.exist?(File.join(root, cmd.sub(%r{\A/}, "")))
        next if operator.match?(/install\b[^\n]*#{Regexp.escape(cmd)}/)

        Finding.new(check: "cron", subject: cmd,
                    detail: "scheduled, not tracked at that path, and OPERATOR.sh does not install it there")
      end
    end

    # PATH is declared in the crontab because cron's own does not include
    # /usr/local/bin, which is where every env-shebang interpreter lives. Four of
    # five jobs had never run for that reason.
    def cron_path_findings
      declared = read("etc", "crontab.vm23")[/^PATH=(.+)$/, 1].to_s.split(":")
      dirs = cron_commands.select { |c| c.start_with?("/") }.map { |c| File.dirname(c) }.uniq
      (dirs - declared).map do |dir|
        Finding.new(check: "cron", subject: dir, detail: "a scheduled command lives here and PATH= does not list it")
      end
    end

    # --- rc.d ----------------------------------------------------------------

    # A service reaches something if a tracked script enables it, or if the
    # service itself says it is deliberately not enabled by default. All four
    # *_jobs workers and irc_gateway take the second route and document the
    # rcctl lines to run by hand, which is a decision rather than a gap.
    def starters
      (Dir.glob(File.join(root, "*.sh")) + Dir.glob(File.join(root, "bin", "*")))
        .select { |f| File.file?(f) }
        .map { |f| File.read(f, encoding: "UTF-8") rescue "" }
        .join("\n")
    end

    def rcd_findings
      enabling = starters
      Dir.glob(File.join(root, "etc", "rc.d", "*")).sort.filter_map do |path|
        name = File.basename(path)
        next if name.end_with?(".tmpl")
        next if enabling.match?(/\b#{Regexp.escape(name)}\b/)
        next if File.read(path, encoding: "UTF-8").match?(/not enabled by default|disabled by default/i)

        Finding.new(check: "rcd", subject: name,
                    detail: "no tracked script enables it and it does not say it is deliberately off")
      end
    end

    # --- zones ---------------------------------------------------------------

    # Both directions. A zone file nsd.conf does not name is a zone nsd will not
    # serve; a name with no file is a zone nsd will refuse to start over. Both
    # are generated from render_dns.rb, so a drift here means someone hand-edited
    # one side.
    def zone_findings
      conf = read("var", "nsd", "etc", "nsd.conf")
      files = Dir.glob(File.join(root, "var", "nsd", "zones", "master", "*.zone"))
                 .map { |f| File.basename(f, ".zone") }
      named = conf.scan(/name:\s*"?([a-z0-9.\-]+)"?/).flatten.uniq

      (files - named).map { |z| Finding.new(check: "zones", subject: z, detail: "zone file nsd.conf does not name") } +
        (named - files).map { |z| Finding.new(check: "zones", subject: z, detail: "nsd.conf names a zone with no file") }
    end

    # --- report --------------------------------------------------------------

    def findings
      cron_findings + cron_path_findings + rcd_findings + zone_findings
    end

    def counts
      { "cron" => cron_commands.size,
        "rcd" => Dir.glob(File.join(root, "etc", "rc.d", "*")).count { |f| !f.end_with?(".tmpl") },
        "zones" => Dir.glob(File.join(root, "var", "nsd", "zones", "master", "*.zone")).size }
    end

    def run(json: false)
      found = findings
      return puts(JSON.pretty_generate(counts: counts, findings: found.map(&:to_h))) if json

      summary = counts.map { |k, v| "#{v} #{k}" }.join(", ")
      puts "openbsd_reach: #{summary} — #{found.size} unreachable"
      found.each { |f| puts "  #{f.check} #{f.subject}: #{f.detail}" }
      found.empty? ? 0 : 1
    end
  end
end

exit Pub4::OpenbsdReach.run(json: ARGV.include?("--json")) if $PROGRAM_NAME == __FILE__
