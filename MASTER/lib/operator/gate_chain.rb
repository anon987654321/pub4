# frozen_string_literal: true

require "open3"
require "rbconfig"
require "operator/ruby_runner"
require "bundler"

module Operator
  # Every gate in the repo, in one order, fixing as it goes.
  #
  # The pieces all existed and nothing ran them together: `bin/gate` held the
  # scanner chain, `MASTER/gates/runner.rb --all` the app gates, `bin/check` the
  # suites, `bin/operator measure` the ratchets, `tools/sprawl_census.rb` the shape of
  # the tree. Five invocations, no run covering the repo, so "is the tree
  # conformant" answered for whichever quarter the last session measured.
  #
  # Three properties the pieces lack apart — why this orchestrates, not aliases:
  #
  #   Attribution. Autofix has broken dilla, postpro and MASTER's own chat path,
  #   so each stage is bracketed by a snapshot of the working tree and reports
  #   the files IT changed, under its own name, rather than leaving one diff for
  #   the next session to bisect.
  #
  #   Foreign dirt. This checkout is shared, so whatever is already modified at
  #   the start is recorded, excluded from every stage's attribution, and printed
  #   at the top before anyone commits it by reflex.
  #
  #   Honest tiers. A stage that measured nothing is neither a pass nor a
  #   failure: it reports as skipped and the run exits 3, the third state
  #   MASTER/gates/runner.rb already spells for a precondition it never met.
  module GateChain
    ROOT = File.expand_path("../../..", __dir__)
    MASTER = File.join(ROOT, "MASTER")
    RUBY = Operator::RubyRunner.gate_ruby
    BUNDLE = Operator::RubyRunner.bundle_cmd

    # Paths nothing writes by hand. `bin/gate` has said in a comment for months
    # that scanner.rb skips `cache` but not `.cache`, so /fix descends into
    # MASTER/tools' generated lora/**/.cache/** copies — a warning with no reader.
    # This is the reader: a rewritten generated file is named, and fails the run.
    GENERATED = %r{/\.cache/|/node_modules/|/public/assets/|/app/assets/builds/|\.lock\z}

    # The panel argues until the late idea arrives and hands back a long list, and
    # an unbounded queue of unattended edits on a shared checkout is the failure
    # this file makes attributable. So the queue has a floor under it.
    PICK_BUDGET = Integer(ENV.fetch("PUB4_GATE_COUNCIL_PICKS", "5"))

    # ok / failed / skipped; skipped is the one that matters.
    Result = Struct.new(:stage, :state, :summary, :changed, keyword_init: true)

    # `mutates` is a claim, and the attribution below tests it: a stage declared
    # non-mutating that changes a file fails the run.
    Stage = Struct.new(:name, :purpose, :mutates, :run, keyword_init: true)

    module_function

    # The entry point, and the two methods under it are the whole of what
    # bin/operator calls. Everything below is a stage or a helper one of these three
    # reaches, so the file reads in the order the ladder runs rather than the
    # order it was written.
    TREES = %w[MASTER RAILS OPENBSD].freeze

    # The outer /fix lifecycle already owns the lexical observation/repair loop.
    # Verification therefore runs every other registered gate without re-entering
    # /fix and returns both its verdict and the files that this verification changed.
    def verify_fix(target:)
      trees = trees_for_target(target)
      selected = stages(scan_only: false, trees:).reject { |stage| stage.name == "lexical" }
      return [0, []] if selected.empty?

      report(selected, scan_only: false, trees:, return_results: true)
    end

    def trees_for_target(target)
      text = target.to_s.strip
      abs = case text.upcase
            when "", ".", "ALL", "EVERYTHING" then ROOT
            when "MASTER" then MASTER
            when "RAILS" then File.join(ROOT, "RAILS")
            when "OPENBSD" then File.join(ROOT, "OPENBSD")
            else File.expand_path(text, ROOT)
            end
      return TREES if abs == ROOT
      return ["RAILS"] if abs == File.join(ROOT, "RAILS") || abs.start_with?("#{File.join(ROOT, "RAILS")}/")
      return ["OPENBSD"] if abs == File.join(ROOT, "OPENBSD") || abs.start_with?("#{File.join(ROOT, "OPENBSD")}/")
      return ["MASTER"] if abs == MASTER || abs.start_with?("#{MASTER}/")

      abort "gate: target is outside pub4 trees: #{target}"
    end

    def run(scan_only:, only: nil, list: false, trees: nil)
      trees = normalise_trees(trees)
      all = stages(scan_only:, trees:)
      selected = only&.any? ? all.select { |stage| only.include?(stage.name) } : all
      abort "gate: no stage named #{only.join(", ")} (have: #{all.map(&:name).join(", ")})" if selected.empty?
      return explain(selected, scan_only:, trees:) if list

      report(selected, scan_only:, trees:)
    end

    # An unknown tree name is refused. The whole point of --tree is to run less,
    # so a typo that quietly narrowed the ladder to nothing would report a clean
    # repo on the strength of having measured none of it.
    def normalise_trees(trees)
      named = Array(trees).flat_map { |value| value.to_s.split(",") }.map(&:upcase).reject(&:empty?)
      return TREES if named.empty?

      unknown = named - TREES
      abort "gate: no tree named #{unknown.join(", ")} (have: #{TREES.join(", ")})" if unknown.any?
      named
    end

    def explain(selected, scan_only:, trees:)
      puts "gate: #{scan_only ? "scan-only" : "full-fix"} — #{selected.size} stage(s) over #{trees.join(", ")}"
      selected.each { |s| puts format("  %-9s %s%s", s.name, s.purpose, s.mutates ? "  [writes]" : "") }
      0
    end