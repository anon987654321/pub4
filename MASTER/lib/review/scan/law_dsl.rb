# frozen_string_literal: true

module Master
  module Review
    module Scan
    # Executable detector adapter DSL. Normative Law identity, scope and universal
    # contract live in data/laws.yml; this DSL binds Ruby detection logic to those
    # catalogue IDs and registers the implementation for scanner execution.
    # Rule subclasses inherit Law.auto_build? == true; specialized laws that
    # need constructor arguments override self.auto_build? = false explicitly.
    #
    #   LawDSL.law :NO_PUTS, applies_to: %i[ruby] do |src, path:|
    #     scan_lines(src, /\bputs\b/, message: "puts in production code")
    #   end
      module LawDSL
        # fires:/does_not_fire: are the Law's own worked examples, checked by
        # test/test_law_fixtures.rb.
        #
        # A scan law fails in one direction far more often than the other: it
        # keeps matching a pattern adjacent to the law it enforces. TIME_ZONE_UNSAFE
        # matched every Time.now when the law is about Time.zone, so it reported 13
        # rewrites of Time.now.utc and Time.now.to_i that would have changed no
        # behaviour. A law that carries the case it must NOT fire on cannot drift
        # that way in silence.
        #
        #   LawDSL.law :TIME_ZONE_UNSAFE, ...,
        #     fires: "Time.now.beginning_of_day",
        #     does_not_fire: "Time.now.utc.iso8601"
        def self.law(id, tags: [], applies_to: nil, autofix: true, description: nil,
                      fires: nil, does_not_fire: nil, example_path: nil, detect_semantic: nil, detect_structural: nil,
                      reads_beyond_file: false, &block)
          raise ArgumentError, "block required" unless block

          dsl_id = id.to_s
          dsl_desc = description || dsl_id.tr("_", " ")
          dsl_tags = Array(tags)
          cls = build_dsl_law_class(dsl_id:, dsl_desc:, dsl_tags:, applies_to:, autofix:, block:,
                                    fires:, does_not_fire:, example_path:, detect_semantic:, detect_structural:)
          cls.define_singleton_method(:reads_beyond_file?) { true } if reads_beyond_file
          cls
        end

        def self.build_dsl_law_class(dsl_id:, dsl_desc:, dsl_tags:, applies_to:, autofix:, block:,
                                           fires: nil, does_not_fire: nil, example_path: nil, detect_semantic: nil, detect_structural: nil)
          cls = Class.new(Law) do
            define_method(:initialize) do
              super()
              @id = dsl_id; @description = dsl_desc
              @severity = self.class.catalogue_severity(dsl_id); @law_tags = dsl_tags; @auto_fix = autofix
            end
            define_method(:check) do |code, path:|
              # Language narrows this deterministic adapter, not the Law's
              # semantic or visual reach. Universal review is handled by those
              # independent streams for every artifact.
              langs = self.class.dsl_langs
              return [] if langs && !langs.include?(language(path)&.to_sym)

              instance_exec(code, path:, &self.class.dsl_block) || []
            end
          end
          dsl_law_attrs(cls, id: dsl_id, block:, langs: applies_to, autofix:, fires:, does_not_fire:, example_path:,
                             detect_semantic:, detect_structural:, tags: dsl_tags)
          cls.class_eval do
            class << self
              attr_reader :dsl_id, :dsl_block, :dsl_langs, :dsl_autofix, :dsl_fires, :dsl_does_not_fire,
                          :dsl_example_path, :dsl_detect_semantic, :dsl_detect_structural, :dsl_tags
            end
          end
          cls
        end

        def self.dsl_law_attrs(cls, attrs)
          attrs.each { |k, v| cls.instance_variable_set("@dsl_#{k}", v) }
        end

      end

    end
  end
end

require_relative "law"
require_relative "../../../law/detectors/lexical_laws"
require_relative "../../../law/detectors/ruby_laws"
require_relative "../../../law/detectors/web_laws"
require_relative "../../../law/detectors/cosmetic_laws"
require_relative "../../../law/detectors/surface_laws"
require_relative "../../../law/detectors/js_laws"
require_relative "../../../law/detectors/universal_laws"
require_relative "../../../law/detectors/structural_laws"
require_relative "../../../law/detectors/structural_question_laws"
require_relative "../../../law/detectors/external_linter_laws"
require_relative "../../../law/detectors/semantic_laws"
require_relative "../../../law/detectors/graph_laws"
require_relative "../../../law/detectors/veto_pattern_law"
require_relative "../../../law/detectors/naming_laws"
require_relative "../../../law/detectors/meta_laws"
require_relative "law_registry_audit"
