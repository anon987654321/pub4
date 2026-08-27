# frozen_string_literal: true

# The repo's instruments, run as one pass, reported as a dmesg.
#
# MASTER converges on "no rule fires". That is not the same as "nothing left
# worth doing", and the gap is most of what a refinement pass finds: a rake task
# nothing calls, a backoff that never sleeps, a mailer aimed at a route that does
# not exist, a gate asserting on the word "rubocop" rather than on whether it
# ran. No rule in data/rules.yml names any of those, because they are not
# properties of a file — they are properties of a claim and its reader.
#
# What already existed: eight instruments that each answer one such question for
# one population — dup_census, data_reach, reader_singularity, rule_reach,
# namespace_ratchet, design_baseline, loc_budget, cohesion. Each with its own
# invocation, its own ceiling file, and no shared vocabulary. `MASTER/bin/pub4 measure`
# aggregates the ratchets; nothing aggregates the *questions*.
#
# This does, per tree, in dmesg form, because a sweep that prints a wall of prose
# is a sweep whose middle nobody reads.
#
#   ruby MASTER/tools/sweep.rb MASTER
#   ruby MASTER/tools/sweep.rb --all
#   ruby MASTER/tools/sweep.rb --all --json
#
# It measures and proposes. It does not land: a ratchet can be moved
# mechanically, a regroup cannot, and a tool that edits on its own judgement is
# the thing DECISIONS.md spent six stages removing. The ledger is what makes the
# loop convergent — see data/proposals.yml.

require "json"
require "yaml"
require "open3"

module Pub4
  module Sweep
    ROOT = File.expand_path("../..", __dir__)
    MASTER = File.join(ROOT, "MASTER")
    LEDGER = File.join(MASTER, "data", "proposals.yml")

    TREES = %w[MASTER RAILS OPENBSD STUDIO].freeze

    # unit name, the tree(s) it speaks for, and how to run it. Each returns
    # [ok, detail] — detail is the dmesg line body, ok is whether the instrument
    # is at or under its recorded low.
    Probe = Struct.new(:unit, :trees, :run, :scoped, keyword_init: true)

    module_function

    def probes
      [
        Probe.new(unit: "spine", trees: %w[MASTER], run: -> { rake("lint:spine") }),
        Probe.new(unit: "locbudget", trees: %w[MASTER], run: -> { rake("loc_budget") }),
        Probe.new(unit: "cohesion", trees: TREES, scoped: true,
                  run: ->(tree) { tool("cohesion.rb", "--census", "--tree=#{tree}") }),
        Probe.new(unit: "dupcensus", trees: %w[MASTER], run: -> { tool("dup_census.rb") }),
        Probe.new(unit: "datareach", trees: %w[MASTER], run: -> { tool("data_reach.rb") }),
        Probe.new(unit: "readersing", trees: %w[MASTER], run: -> { tool("reader_singularity.rb") }),
        Probe.new(unit: "rulereach", trees: %w[MASTER], run: -> { tool("rule_reach.rb") }),
        Probe.new(unit: "namespace", trees: %w[MASTER], run: -> { tool("namespace_ratchet.rb") }),
        Probe.new(unit: "designbase", trees: %w[RAILS], run: -> { tool("design_baseline.rb") }),
# OPENBSD's declarations and their readers live in different files by
# design — crontab names a path, OPERATOR.sh installs it, rc.d holds the
# service, nsd.conf names the zone — and nothing failed when a pair
# stopped agreeing.
Probe.new(unit: "obsdreach", trees: %w[OPENBSD],
          run: -> { sibling("OPENBSD", "tools/reach.rb") }),
# STUDIO's coverage was never thin, only unreported here: gate.rb parses
# every first-party file, checks dilla's manifest against the disk, and
# boots the guarded entry points. `rake studio` already runs it; this is
# what makes its result visible in a sweep.
Probe.new(unit: "studiogate", trees: %w[STUDIO],
          run: -> { sibling("STUDIO", "gate.rb") }),
        Probe.new(unit: "instruments", trees: %w[MASTER], run: -> { tool("instruments.rb") }),
        Probe.new(unit: "constcoll", trees: %w[MASTER], run: -> { tool("constant_collisions.rb") }),
        Probe.new(unit: "secsweep", trees: %w[MASTER], run: -> { tool("security_sweep.rb") }),
      ]
    end

    def tool(name, *args)
      capture(RbConfig.ruby, File.join(MASTER, "tools", name), *args)
    end

# Run from the sibling's own directory. MASTER requires nothing from the
# other trees and they resolve their own relative paths; a probe is a
# subprocess for the same reason rake studio_gate is one.
def sibling(tree, script, *args)
  dir = File.join(ROOT, tree)
  capture(RbConfig.ruby, File.join(dir, script), *args, chdir: dir)
end

    def rake(task)
      capture(RbConfig.ruby, "-S", "rake", task, chdir: MASTER)
    end

    def capture(*cmd, chdir: MASTER)
      out, err, status = Open3.capture3(*cmd, chdir: chdir)
      body = "#{out}#{err}".lines.map(&:rstrip).reject(&:empty?)
      [status.success?, body]
    rescue StandardError => e
      [false, ["#{e.class}: #{e.message}"]]
    end

    # The last line an instrument prints is its verdict; the rest is evidence.
    # dmesg is one line per device, so the verdict attaches and the evidence
    # follows indented only when the verdict is bad.
    # The instrument's own summary line — the one it prefixes with its name —
# not simply the last line printed. design_baseline emits its summary before
# its per-app detail, so "last line" reported a detail row as the verdict and
# hid a live violation behind it.
def verdict(body)
  summary = body.reverse.find { |l| l.match?(/\A[a-z][a-z_]*:\s/) }
  (summary || body.last).to_s.sub(/\A\w+[_a-z]*:\s*/, "")
end

    def dmesg(line) = puts(line.to_s.gsub(/\s+/, " ").strip)

    def sweep(tree, unit_index)
      dmesg "#{tree.downcase}0 at sweep0: #{tree_summary(tree)}"
      rows = probes.select { |p| p.trees.include?(tree) }
      rows.each_with_index do |probe, i|
        ok, body = probe.scoped ? probe.run.call(tree) : probe.run.call
        dmesg "#{probe.unit}#{unit_index + i} at #{tree.downcase}0: #{verdict(body)}"
        next if ok

        summary = verdict(body)
        body.reject { |l| l.include?(summary) }.last(4).each { |l| dmesg "  #{probe.unit}#{unit_index + i}: #{l}" }
      end
      rows.map.with_index { |p, i| [p.unit, unit_index + i] }
    end

    def tree_summary(tree)
      files = Dir.glob(File.join(ROOT, tree, "**", "*.rb"))
                 .reject { |f| f.match?(%r{/(vendor|node_modules|tmp|\.git|knowledge|output)/}) }
      lines = files.sum { |f| File.foreach(f).count rescue 0 }
      "#{files.size} files, #{lines} lines"
    end

    def ledger
      return { "proposals" => [] } unless File.exist?(LEDGER)

      YAML.safe_load_file(LEDGER) || { "proposals" => [] }
    end

    def ledger_counts
      rows = ledger.fetch("proposals", [])
      rows.group_by { |r| r["state"] }.transform_values(&:size)
    end

    def run(trees, json: false)
      return puts(JSON.pretty_generate(trees: trees.to_h { |t| [t, probes.select { |p| p.trees.include?(t) }.map(&:unit)] })) if json

      dmesg "sweep0 at pub4 root: #{trees.join(' ')}"
      dmesg "real files = #{Dir.glob(File.join(ROOT, '**', '*.rb')).size} avail probes = #{probes.size}"
      idx = 0
      trees.each { |tree| idx += sweep(tree, idx).size }

      counts = ledger_counts
      dmesg "ledger0 at sweep0: open=#{counts['open'].to_i} landed=#{counts['landed'].to_i} " \
            "refuted=#{counts['refuted'].to_i}"
      dmesg "root on #{trees.first.downcase}0 swap on ledger0 dump on ledger0"
      0
    end
  end
end

if $PROGRAM_NAME == __FILE__
  json = ARGV.include?("--json")
  trees = ARGV.include?("--all") ? Pub4::Sweep::TREES : ARGV.reject { |a| a.start_with?("--") }
  trees = %w[MASTER] if trees.empty?
  bad = trees - Pub4::Sweep::TREES
  abort "sweep: unknown tree(s): #{bad.join(', ')}" if bad.any?
  exit Pub4::Sweep.run(trees, json:)
end
