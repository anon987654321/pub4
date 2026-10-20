# frozen_string_literal: true

# Where a name is defined, across all four trees.
#
#   ruby MASTER/tools/where.rb Chords          # every module, class, method or constant called Chords
#   ruby MASTER/tools/where.rb session.rb      # every file with that basename
#
# Nine files in this repository are called engine.rb and six are called session.rb, so a file search
# for either lands on the wrong one. This names the definition, with its tree, file and line.

require "open3"

module Operator
  module Where
    REPO_ROOT = File.expand_path("../..", __dir__)

    module_function

    def definitions(name)
      escaped = Regexp.escape(name)
      pattern = "^[[:space:]]*(module|class)[[:space:]]+([A-Za-z_:]+::)?#{escaped}([[:space:]]|$|<)|" \
                "^[[:space:]]*def[[:space:]]+(self\\.)?#{escaped}[?!=]?([[:space:](]|$)|^[[:space:]]*#{escaped}[[:space:]]*="
      out, = Open3.capture2("git", "-C", REPO_ROOT, "grep", "-nE", pattern, "--", "*.rb")
      out.lines.map(&:chomp)
    end

    def files(name)
      out, = Open3.capture2("git", "-C", REPO_ROOT, "ls-files", "--", "*/#{name}", name)
      out.lines.map(&:chomp)
    end

    def run(argv)
      name = argv.first or abort "usage: where.rb NAME"
      rows = name.include?(".") ? files(name) : definitions(name)
      rows.each { |row| puts row }
      warn "#{rows.size} found" if rows.empty? || rows.size > 1
      rows.empty? ? 1 : 0
    end
  end
end

exit Operator::Where.run(ARGV) if $PROGRAM_NAME == __FILE__
