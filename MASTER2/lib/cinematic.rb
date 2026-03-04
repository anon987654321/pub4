# frozen_string_literal: true

require "time"

module Cinematic
  class Engine
    Result = Struct.new(:ok?, :preset, :style, :errors, keyword_init: true)

    def initialize(preset_model:, style_model:)
      @preset_model = preset_model
      @style_model = style_model
    end

    def execute(preset_name:, style_hint: nil, attributes: {})
      return failure(["preset_name is required"]) if blank?(preset_name)

      style = discover_style(style_hint)
      return failure(["style not found"]) unless style

      preset = save_preset(preset_name: preset_name, style: style, attributes: attributes)
      return failure(preset.errors.full_messages) unless preset.persisted?

      Result.new(ok?: true, preset: preset, style: style, errors: [])
    end

    def save_preset(preset_name:, style:, attributes:)
      preset = find_or_initialize_preset(preset_name)
      assign_preset_attributes(preset, style, attributes)
      persist_preset(preset)
      preset
    end

    def discover_style(style_hint)
      return default_style if blank?(style_hint)

      find_style_by_key(style_hint) || find_style_by_name(style_hint) || default_style
    end

    private

    attr_reader :preset_model, :style_model

    def find_or_initialize_preset(preset_name)
      preset_model.includes(:style).find_or_initialize_by(name: preset_name)
    end

    def assign_preset_attributes(preset, style, attributes)
      preset.style = style
      preset.metadata ||= {}
      preset.metadata.merge!(safe_hash(attributes))
      preset.updated_at = current_timestamp
    end

    def persist_preset(preset)
      preset.save!
    rescue StandardError
      preset
    end

    def find_style_by_key(key)
      style_model.includes(:presets).find_by(key: key.to_s)
    end

    def find_style_by_name(name)
      style_model.includes(:presets).find_by(name: name.to_s)
    end

    def default_style
      style_model.includes(:presets).order(:id).first
    end

    def current_timestamp
      Time.now.utc
    end

    def safe_hash(value)
      value.is_a?(Hash) ? value : {}
    end

    def blank?(value)
      value.nil? || (value.respond_to?(:empty?) && value.empty?)
    end

    def failure(errors)
      Result.new(ok?: false, preset: nil, style: nil, errors: Array(errors))
    end
  end
end