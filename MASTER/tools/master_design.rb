# frozen_string_literal: true

require "yaml"

module Operator
  # The design-tier rules of MASTER/data/laws.yml, as the block map that gates
  # and lints read.
  #
  # Five gates and one lint each opened that file and dug `["design_rules"]`
  # themselves, and each resolved the path its own way. When the design blocks
  # became rules -- `tier: design`, the old section under `config` -- that was
  # six edits for one shape change, and the next shape change would be six
  # again.
  #
  # It lives here rather than under gates/ because shared/ is what each app
  # vendors onto the VPS: rhythm_lint runs there, gates do not.
  module MasterDesign
    module_function

    # Prefer an explicit monorepo root when a deployed app provides one.
    # Otherwise derive the source checkout from this file; never assume a
    # developer's home directory.
    def laws_path
      source = File.expand_path("../data/laws.yml", __dir__)
      configured = ENV["PUB4_RAILS_ROOT"].to_s.strip
      candidates = [
        (File.join(File.dirname(configured), "MASTER/data/laws.yml") unless configured.empty?),
        source,
      ].compact
      candidates.find { |candidate| File.readable?(candidate) }
    end

    def document(path = laws_path)
      return {} unless path && File.file?(path)

      YAML.safe_load_file(path, aliases: true) || {}
    end

    def blocks(path = laws_path) = document(path)["tokens"] || {}

    def tokens(path = laws_path) = document(path)["tokens"] || {}

    def dig(*keys, path: laws_path) = blocks(path).dig(*keys.map(&:to_s))
  end
end
