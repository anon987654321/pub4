# frozen_string_literal: true

require "yaml"

module Operator
  # RAILS-local reader for MASTER design data. It reads the constitution as data;
  # it does not load MASTER code.
  module MasterDesign
    module_function

    def tokens_path
      root = File.expand_path("../../../..", __dir__)
      path = File.join(root, "MASTER", "data", "tokens.yml")
      File.readable?(path) ? path : nil
    end

    def document(path = tokens_path)
      return {} unless path && File.file?(path)

      YAML.safe_load_file(path, aliases: true) || {}
    end

    def blocks(path = tokens_path) = document(path)["tokens"] || {}

    def tokens(path = tokens_path) = document(path)["tokens"] || {}

    # Compatibility name retained at the canonical reader: design_system is the token map.
    def design_system(path = tokens_path) = tokens(path)

    def dig(*keys, path: tokens_path) = blocks(path).dig(*keys.map(&:to_s))
  end
end
