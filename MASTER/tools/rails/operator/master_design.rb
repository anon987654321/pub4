# frozen_string_literal: true

require "yaml"

module Operator
  # RAILS-local reader for MASTER design data. It reads the constitution as data;
  # it does not load MASTER code.
  module MasterDesign
    module_function

    def laws_path
      root = File.expand_path("../../../..", __dir__)
      path = File.join(root, "MASTER", "data", "laws.yml")
      File.readable?(path) ? path : nil
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
