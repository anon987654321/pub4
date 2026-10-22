# frozen_string_literal: true

require "set"

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
      @lock = Mutex.new

      module_function

      def note(lines)
        found = Array(lines).flat_map { |line| line.to_s.scan(PATH).flatten }.grep_v(IGNORED)
        @lock.synchronize { @named.merge(found) }
        found.size
      end

      def named = @lock.synchronize { @named.dup }

      def reset! = @lock.synchronize { @named.clear }

      def covers?(path)
        text = path.to_s
        named.any? { |token| text == token || text.end_with?("/#{token}") }
      end

      # The same files, those a red gate names first, the order otherwise kept.
      def first(files)
        focused, rest = Array(files).partition { |path| covers?(path) }
        focused + rest
      end
    end
  end
end
