# frozen_string_literal: true

require "set"
require "yaml"

module Master
  module Fix
    # The files a red gate names, read from the pre-repair proof: a failing test's location, a stack
    # frame, a gate's failure line. /fix scans and repairs these first, so a run spends its budget
    # on what keeps a gate red before the long tail of style findings.
    module GateFocus
      PATH = %r{(?<![\w/.-])((?:[\w.-]+/)*[\w.-]+\.(?:rb|rake|erb|scss|css|js|mjs|yml|ksh|sh))\b}
      # Files that appear in nearly every stack trace say nothing about which gate they broke.
      IGNORED = %r{(?:\A|/)(?:gems|ruby/\d|minitest|bundler)/}

      @named = Set.new
      @blockers = false
      @plan = false
      @lock = Mutex.new

      module_function

      def note(lines)
        found = Array(lines).flat_map { |line| line.to_s.scan(PATH).flatten }.grep_v(IGNORED)
        @lock.synchronize { @named.merge(found) }
        found.size
      end

      def named = @lock.synchronize { @named.dup }

      def reset! = @lock.synchronize { @named.clear }

      # --blockers: this run repairs only the files a red gate names, and reads none semantically.
      def blockers! = @lock.synchronize { @blockers = true }
      def blockers? = @lock.synchronize { @blockers == true }
      def restore_blockers(value) = @lock.synchronize { @blockers = value }

      # --plan: this run takes the read-only gate baseline and prints the worklist, writing nothing.
      def plan! = @lock.synchronize { @plan = true }
      def plan? = @lock.synchronize { @plan == true }
      def restore_plan(value) = @lock.synchronize { @plan = value }

      def covers?(path)
        text = path.to_s
        named.any? { |token| text == token || text.end_with?("/#{token}") }
      end

      # Only the files a red gate names.
      def only(files) = Array(files).select { |path| covers?(path) }

      # The same files, those a red gate names first, the order otherwise kept.
      def first(files)
        focused, rest = Array(files).partition { |path| covers?(path) }
        focused + rest
      end
    end

    # Splits the gates a proof left red into hard and soft (data/gate_tiers.yml). A run with a
    # hard gate red cannot call itself done; a soft gate red is reported and left for later.
    module GateTiers
      FILE = File.expand_path("../../data/gate_tiers.yml", __dir__)

      module_function

      def soft = @soft ||= Array(YAML.safe_load_file(FILE)&.fetch("soft", [])).map(&:to_s).freeze

      def hard?(gate) = !soft.include?(gate.to_s)

      # [hard, soft] red gates, each sorted.
      def split(failing)
        hard, rest = Array(failing).map(&:to_s).partition { |gate| hard?(gate) }
        [hard.sort, rest.sort]
      end
    end
  end
end
