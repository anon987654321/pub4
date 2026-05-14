# frozen_string_literal: true

require "open3"

module Master
  module Loop
  # Act-react superloop: for each rule, run its inner RuleLoop to convergence,
  # then check if anything remains. Itself autoloops indefinitely — sleeping
  # IDLE_SLEEP between passes when clean, restarting immediately when violations exist.
  #
  # Granularity levels scanned per pass:
  #   :line    — lexical regex (TableLexicalRule)
  #   :unit    — method/class/paragraph blocks (SemanticRule per-unit)
  #   :section — file-level structural (all rules against whole file)
  #   :tree    — codebase-level coupling (InterconnectRule, CoChangeCouplingRule)
  class SuperLoop
    IDLE_SLEEP      = 300   # seconds between clean passes
    STARTUP_DELAY   = 90    # seconds before first self-run after boot
    SCAN_GLOB       = Master::Judge::Scan::Scanner::SCAN_GLOB
    SKIP_DIRS       = %w[vendor/ knowledge/ node_modules/ .git/ .bundle/ tmp/ log/ dist/].freeze
    GIT_COMMIT_MSG  = "super_loop: autofix violations".freeze

    def initialize(rules:, agent:, scanner:, root:, bus: nil, git: nil)
      @rules   = rules
      @agent   = agent
      @scanner = scanner
      @root    = root
      @bus     = bus
      @git     = git || GitOperations.new(root)
    end

    # One-shot: run all rule loops once against target. Returns Result.
    def run_once(target = @root)
      files = collect_files(target)
      pass(files)
    end

    # Continuous: run forever. Sleeps IDLE_SLEEP when clean, retries immediately when dirty.
    # Runs in the caller's thread — launch via Thread.new for background.
    def run_forever(target = @root)
      sleep STARTUP_DELAY
      loop do
        files  = collect_files(target)
        result = pass(files)
        any_dirty = result[:rule_results].any? { |r| r[:status] != :clean }
        @bus&.publish("super_loop:pass", target:, any_dirty:,
                      rules: result[:rule_results].size,
                      fixed: result[:rule_results].sum { |r| r[:fixed] })
        if any_dirty
          commit_if_dirty
        else
          @bus&.publish("super_loop:idle", sleep: IDLE_SLEEP)
          sleep IDLE_SLEEP
        end
      end
    rescue StandardError => e
      @bus&.publish("super_loop:error", error: e.message)
      Result.err("super_loop: #{e.message}", category: :unknown)
    end

    private

    def pass(files)
      rule_results = @rules.map do |rule|
        loop = RuleLoop.new(rule:, agent: @agent, scanner: @scanner, root: @root, bus: @bus, git: @git)
        result = loop.run(files)
        @bus&.publish("super_loop:rule_result", rule: rule.id, **result)
        result.merge(rule: rule.id)
      end
      { rule_results: }
    end

    def collect_files(target)
      Dir.glob(File.join(target, "**", "*"))
         .select { |f| File.file?(f) }
         .reject { |f| SKIP_DIRS.any? { |d| f.include?(d) } }
         .select { |f| SCAN_GLOB.match?(File.basename(f)) rescue true }
         .sort
    end

    def commit_if_dirty
      return unless @git&.dirty?(".")
      @git.add_lib_files
      @git.commit(GIT_COMMIT_MSG)
    rescue StandardError => e
      @bus&.publish("super_loop:commit_error", error: e.message)
    end
  end
  end
end
