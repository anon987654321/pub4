# frozen_string_literal: true

module Master
  module Operator
    # Owns the one read of the open operator debt: Operator::StatusReport#backlog_open_count delegates here rather
    # than counting a second way, which is how one of the two copies of the old
    # register stayed broken unnoticed for as long as it did.
    #
    # The per-tree backlog files were consolidated into the repo-root TODO.md.
    # Open operator debt now lives under its OPENBSD section, one item per hidden
    # "<!-- open-debt -->" marker line; this counts those.
    module OperatorDocs
      # __dir__ is MASTER/lib/operator, so the repo root is three levels up, not four.
      # At four this resolved to the directory *containing* the checkout, the path
      # was absent, and every method degraded to its empty default without raising.
      ROOT = File.expand_path("../../..", __dir__)
      DEBT_RELATIVE = "TODO.md"
      DEBT_PATH = File.join(ROOT, DEBT_RELATIVE)
      OPEN_DEBT_MARKER = "<!-- open-debt -->"

      module_function

      # root: so the cross-repo diagnostic can pass its own checkout rather than
      # inheriting this file's idea of where the repo is. Counts marker lines,
      # not substrings, so prose that names the marker cannot inflate the number.
      def open_debt_count(root: ROOT)
        path = root == ROOT ? DEBT_PATH : File.join(root, DEBT_RELATIVE)
        return 0 unless File.file?(path)

        File.readlines(path).count { |line| line.strip == OPEN_DEBT_MARKER }
      end
    end
  end
end
