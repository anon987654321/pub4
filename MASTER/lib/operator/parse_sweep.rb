# frozen_string_literal: true

require "prism"

module Operator

  # Does every Ruby file in the tree parse? Answered in one process with Prism,
  # so the whole repository takes seconds where `ruby -c` per file takes minutes.
  #
  # The pre-commit hook already refuses a staged file that does not parse, and a
  # missing comma in command_registry/chat.rb still sat on main for three hours:
  # the hook lives in a core.hooksPath that only `bin/operator hooks` sets, and
  # the clone that committed it never ran that. A check that depends on being
  # installed is not a check, so this one is run by the things that cannot skip
  # it: doctor, fix-here before it spends a model call, and CI on every push.
  module ParseSweep
    Failure = Data.define(:path, :line, :message)

    module_function

    # A git that cannot list the tree has measured nothing, so it raises rather than
    # reporting an empty list that every caller reads as "everything parses".
    def tracked(root)
      out = IO.popen(["git", "-C", root, "ls-files", "-z", "--", "*.rb"], err: File::NULL, &:read)
      raise "parse_sweep: git ls-files failed under #{root}" unless $?.success?

      out.split("\0").reject(&:empty?)
    end

    def failures(root, paths = tracked(root))
      paths.filter_map do |path|
        full = File.join(root, path)
        next unless File.file?(full)

        error = Prism.parse_file(full).errors.first
        Failure.new(path:, line: error.location.start_line, message: error.message) if error
      end
    end

    def render(failures)
      failures.map { |f| "#{f.path}:#{f.line}, #{f.message}" }.join("\n")
    end
  end
end
