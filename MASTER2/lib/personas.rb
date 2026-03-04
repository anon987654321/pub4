# frozen_string_literal: true

require "yaml"

module Paths
  module_function

  def load_data_file(path, default: {})
    return default unless path && File.exist?(path)

    yaml = File.read(path)
    YAML.safe_load(yaml, permitted_classes: [], aliases: false) || default
  rescue Psych::SyntaxError
    default
  end
end

module Personas
  DATA_DIR = File.expand_path("personas", __dir__)
  DATA_FILE = File.join(DATA_DIR, "personas.yml")
  DEFAULT_SYSTEM_PROMPT = "You are a helpful assistant."

  module_function

  def data
    @data ||= Paths.load_data_file(DATA_FILE, default: {})
  end

  def data_for(persona_key)
    data.fetch(persona_key.to_s, {})
  end

  def system_prompt(persona_key:)
    data_for(persona_key).fetch("system_prompt", DEFAULT_SYSTEM_PROMPT)
  end

  def active_persona_keys(scope: ::Persona.all)
    scope.where(active: true).pluck(:key)
  end

  def active_personas(scope: ::Persona.all)
    scope.where(active: true).includes(:axioms)
  end

  def persona_display_names(scope: ::Persona.all)
    scope.where(active: true).pluck(:key, :display_name).to_h
  end
end