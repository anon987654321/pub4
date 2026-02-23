# frozen_string_literal: true

require "yaml"

module MASTER
  class Executor
    # Prompts — loads strategy prompt templates from data/prompts/*.yml
    # Templates use Ruby's % formatting: "%{goal}", "%{tool_list}", etc.
    module Prompts
      PROMPTS_DIR = Paths.data_file("prompts").freeze

      module_function

      def load(strategy)
        @cache ||= {}
        @cache[strategy] ||= begin
          file = File.join(PROMPTS_DIR, "#{strategy}.yml")
          File.exist?(file) ? YAML.safe_load_file(file) : {}
        rescue StandardError
          {}
        end
      end

      def get(strategy, key, **vars)
        template = load(strategy).fetch(key.to_s, "")
        vars.empty? ? template : template % vars
      rescue KeyError => err
        raise ArgumentError, "Prompt #{strategy}/#{key} missing variable: #{err.message}"
      end
    end
  end
end
