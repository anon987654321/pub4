# frozen_string_literal: true

module Master
  module Review
    module Scan
    # Inline Ruby Law definition — executable alternative to laws.yml entries.
    # Defined rules auto-register via Law.inherited; no YAML required.
    # Rule subclasses inherit Law.auto_build? == true; specialized rules that
    # need constructor arguments override self.auto_build? = false explicitly.
    #
    #   LawDSL.law :NO_PUTS, severity: :warning, applies_to: %i[ruby] do |src, path:|
    #     scan_lines(src, /\bputs\b/, message: "puts in production code")
    #   end
      module LawDSL
        # fires:/does_not_fire: are the Law's own worked examples, checked by
        # test/test_rule_fixtures.rb.
        #
        # A scan rule fails in one direction far more often than the other: it
        # keeps matching a pattern adjacent to the law it enforces. TIME_ZONE_UNSAFE
        # matched every Time.now when the law is about Time.zone, so it reported 13
        # rewrites of Time.now.utc and Time.now.to_i that would have changed no
        # behaviour. A rule that carries the case it must NOT fire on cannot drift
        # that way in silence.
        #
        #   LawDSL.law :TIME_ZONE_UNSAFE, ...,
        #     fires: "Time.now.beginning_of_day",
        #     does_not_fire: "Time.now.utc.iso8601"
        def self.law(id, severity: :warning, tags: [], applies_to: nil, autofix: true, description: nil,
                      fires: nil, does_not_fire: nil, example_path: nil, detect_semantic: nil, detect_structural: nil, &block)
          raise ArgumentError, "block required" unless block

          dsl_id = id.to_s
          dsl_desc = description || dsl_id.tr("_", " ")
          dsl_tags = Array(tags)
          build_dsl_law_class(dsl_id:, dsl_desc:, dsl_tags:, severity:, applies_to:, autofix:, block:,
                                fires:, does_not_fire:, example_path:, detect_semantic:, detect_structural:)
        end

        def self.build_dsl_law_class(dsl_id:, dsl_desc:, dsl_tags:, severity:, applies_to:, autofix:, block:,
                                           fires: nil, does_not_fire: nil, example_path: nil, detect_semantic: nil, detect_structural: nil)
          cls = Class.new(Law) do
            define_method(:initialize) do
              super()
              @id = dsl_id; @description = dsl_desc
              @severity = severity; @rule_tags = dsl_tags; @auto_fix = autofix
            end
            define_method(:check) do |code, path:|
              langs = self.class.dsl_langs
              return [] if langs && !langs.include?(language(path)&.to_sym)

              instance_exec(code, path:, &self.class.dsl_block) || []
            end
          end
          dsl_law_attrs(cls, block:, langs: applies_to, autofix:, fires:, does_not_fire:, example_path:, detect_semantic:, detect_structural:)
          cls.class_eval { class << self; attr_reader :dsl_block, :dsl_langs, :dsl_autofix, :dsl_fires, :dsl_does_not_fire, :dsl_example_path, :dsl_detect_semantic, :dsl_detect_structural; end }
          cls
        end

        def self.dsl_law_attrs(cls, attrs)
          attrs.each { |k, v| cls.instance_variable_set("@dsl_#{k}", v) }
        end

      end

      # Compatibility API; new code should speak in Law terms.
      LawDSL.define_singleton_method(:rule) { |*args, **kwargs, &block| law(*args, **kwargs, &block) }
      RuleDSL = LawDSL
    end
  end
end

require_relative "law"
require_relative "laws/lexical_rules"
require_relative "laws/ruby_rules"
require_relative "laws/web_rules"
require_relative "laws/cosmetic_rules"
require_relative "laws/surface_rules"
require_relative "laws/js_rules"
require_relative "laws/universal_rules"
require_relative "laws/structural_rules"
require_relative "laws/structural_question_rules"
require_relative "laws/external_linter_rules"
require_relative "laws/semantic_rules"
require_relative "laws/graph_rules"
require_relative "laws/yaml_bridge_rules"
require_relative "laws/naming_rules"
require_relative "laws/meta_rules"
# The registry is what these requires load, and this one was missing: nothing
# reached law_bridge_rule until InfraHelpers const_get'd it while building a
# scanner, so `Law.registry` held 144 rules in a fresh process and 145 after
# anything scanned. Every census over the registry read whichever number its
# load order happened to produce — rule_deps.ungraphed 133 alone and 134 under
# a run that had scanned.
require_relative "laws/law_bridge_rule"
require_relative "infra_helpers"
require_relative "law_registry_audit"
