# frozen_string_literal: true

require "yaml"

module Pub4
  # The design-tier rules of MASTER/data/rules.yml, as the block map that gates
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

    # The deploy layout is not the repo layout -- each app carries its own copy
    # of shared/, so the relative walk that works here resolves to nothing on
    # the box. PUB4_RAILS_ROOT is set by the runner when it knows better.
    def rules_path
      [ ENV["PUB4_RAILS_ROOT"] && File.join(File.dirname(ENV["PUB4_RAILS_ROOT"]), "MASTER/data/rules.yml"),
        "/home/dev/pub4/MASTER/data/rules.yml",
        File.expand_path("../../../../MASTER/data/rules.yml", __dir__) ]
        .compact.find { |candidate| File.readable?(candidate) }
    end

    def blocks(path = rules_path)
      return {} unless path && File.file?(path)

      rules = (YAML.safe_load_file(path, aliases: true) || {})["rules"]
      Array(rules.is_a?(Hash) ? rules.values.flatten : rules)
        .select { |rule| rule.is_a?(Hash) && rule["tier"] == "design" && rule["config"].is_a?(Hash) }
        .to_h { |rule| [ rule["id"].to_s.downcase, rule["config"] ] }
    end

    def dig(*keys, path: rules_path) = blocks(path).dig(*keys.map(&:to_s))
  end
end
