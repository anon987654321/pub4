# frozen_string_literal: true

module Cinematic
  class Templates
    SYMBOL_KEYS = %i[name description template].freeze

    FIELD_SNIPPET = lambda do |name, description, type|
      %("#{name}" => { description: "#{description}", type: "#{type}" })
    end

    def self.presets(scope: Cinematic::Preset)
      scope.includes(:items).order(:name).map do |preset|
        symbolize_keys(
          name: preset.name,
          description: preset.description.to_s,
          template: build_template_from_items(preset.items)
        )
      end
    end

    def self.discover_models(base: ActiveRecord::Base)
      models = base.descendants
      models = models.reject(&:abstract_class?)
      models = models.reject { |m| m.name.blank? }
      models.sort_by(&:name)
    end

    def self.schema_snippets
      [
        FIELD_SNIPPET.call("title", "Human readable title", "string"),
        FIELD_SNIPPET.call("summary", "Short summary", "string"),
        FIELD_SNIPPET.call("tags", "List of tags", "array")
      ].join(",\n")
    end

    def self.build_template_from_items(items)
      items.map { |item| template_line(item) }.compact.join("\n")
    end
    private_class_method :build_template_from_items

    def self.template_line(item)
      return if item.nil?

      %(#{item.key}: #{item.value})
    end
    private_class_method :template_line

    def self.symbolize_keys(hash)
      SYMBOL_KEYS.each_with_object({}) { |k, out| out[k] = hash[k] }
    end
    private_class_method :symbolize_keys
  end
end