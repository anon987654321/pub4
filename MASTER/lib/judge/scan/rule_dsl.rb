# frozen_string_literal: true

module Master
  module Judge
    module Scan
    # Inline Ruby rule definition — JE-style alternative to rules.yml entries.
    # Defined rules auto-register via Rule.inherited; no YAML required.
    # Rule subclasses inherit Rule.auto_build? == true; specialized rules that
    # need constructor arguments override self.auto_build? = false explicitly.
    #
    #   RuleDSL.rule :NO_PUTS, severity: :warning, applies_to: %i[ruby] do |src, path:|
    #     scan_lines(src, /\bputs\b/, message: "puts in production code")
    #   end
      module RuleDSL
        def self.rule(id, severity: :warning, tags: [], applies_to: nil, autofix: true, description: nil, &block)
          raise ArgumentError, "block required" unless block
          dsl_id = id.to_s.upcase
          dsl_desc = description || dsl_id.tr("_", " ")
          dsl_tags = Array(tags)
          Class.new(Rule) do
            @dsl_block = block
            @dsl_langs = applies_to
            @dsl_autofix = autofix
            class << self; attr_reader :dsl_block, :dsl_langs, :dsl_autofix; end
            define_method(:initialize) do
              super()
              @id = dsl_id; @description = dsl_desc
              @severity = severity; @rule_tags = dsl_tags; @auto_fix = autofix
            end
            define_method(:check) do |code, path:|
              langs = self.class.dsl_langs
              return [] if langs && !langs.include?(language(path)&.to_sym)
              instance_exec(code, path: path, &self.class.dsl_block)
            end
          end
        end
      end
    end
  end
end

require_relative "rules/lexical_rules"
require_relative "rules/ruby_rules"
require_relative "rules/web_rules"
require_relative "rules/js_rules"
require_relative "rules/universal_rules"
require_relative "rules/structural_rules"
