# frozen_string_literal: true

require "yaml"

module Operator
  # Owns the one read of the open operator debt: StatusReport#backlog_open_count
  # delegates here rather than counting a second way.
  #
  # Open operator debt is the seams in MASTER/data/operator_seams.yml, one
  # entry each; this counts those.
  module OperatorDocs
    # __dir__ is MASTER/lib/operator, so the repo root is three levels up, not four.
    # At four this resolved to the directory *containing* the checkout, the path
    # was absent, and every method degraded to its empty default without raising.
    ROOT = File.expand_path("../../..", __dir__)
    DEBT_RELATIVE = "MASTER/data/operator_seams.yml"
    DEBT_PATH = File.join(ROOT, DEBT_RELATIVE)

    module_function

    # root: so the cross-repo diagnostic can pass its own checkout rather than
    # inheriting this file's idea of where the repo is.
    def open_debt_count(root: ROOT)
      path = root == ROOT ? DEBT_PATH : File.join(root, DEBT_RELATIVE)
      return 0 unless File.file?(path)

      seams = (YAML.safe_load_file(path) || {}).fetch("seams", [])
      seams.is_a?(Array) ? seams.size : 0
    end
  end
end
