# frozen_string_literal: true

require "yaml"

module Paths
  module_function

  def load_data_file(path, default: {})
    return default unless path && File.file?(path)

    YAML.safe_load_file(path, permitted_classes: [], aliases: true) || default
  rescue StandardError => e
    Logging.warn("Failed to load YAML data file: #{path} (#{e.class}: #{e.message})")
    default
  end
end

module Executor
  class Context
    IDENTITY_KEY = "identity"
    DEFAULT_LANGUAGE = "en"
    MAX_SYSTEM_MESSAGE_CHARS = 12_000
    FILE_PREVIEW_SLICE_CHARS = 800
    FILE_PREVIEW_TRUNCATION_SUFFIX = "\n...[truncated]...\n"
    DEFAULT_IDENTITY = {
      "name" => "Assistant",
      "role" => "helpful assistant",
      "language" => DEFAULT_LANGUAGE
    }.freeze

    def initialize(execution:)
      @execution = execution
    end

    def build_system_message
      sections = [
        header_section,
        identity_section,
        runtime_section,
        instructions_section,
        repository_section,
        safety_section
      ].compact

      message = sections.join("\n\n").strip
      message = message[0, MAX_SYSTEM_MESSAGE_CHARS] if message.length > MAX_SYSTEM_MESSAGE_CHARS
      message
    end

    def identity
      @identity ||= load_identity
    end

    def recent_messages(limit: 50)
      return [] unless @execution&.respond_to?(:messages)

      @execution
        .messages
        .includes(:tool_calls, :attachments)
        .order(:created_at)
        .last(limit)
    rescue StandardError => e
      Logging.warn("Failed to load recent messages (#{e.class}: #{e.message})")
      []
    end

    private

    def header_section
      "You are the system context for this execution."
    end

    def identity_section
      data = identity
      return nil unless data.is_a?(Hash)

      name = data["name"] || DEFAULT_IDENTITY["name"]
      role = data["role"] || DEFAULT_IDENTITY["role"]
      language = data["language"] || DEFAULT_IDENTITY["language"]

      [
        "Identity:",
        "- name: #{name}",
        "- role: #{role}",
        "- language: #{language}"
      ].join("\n")
    end

    def runtime_section
      return nil unless @execution

      parts = []
      parts << "Execution:"
      parts << "- id: #{@execution.id}" if @execution.respond_to?(:id)
      parts << "- created_at: #{@execution.created_at}" if @execution.respond_to?(:created_at)
      parts.join("\n")
    end

    def instructions_section
      instructions = execution_instructions
      return nil unless instructions && !instructions.strip.empty?

      "Instructions:\n#{instructions.strip}"
    end

    def repository_section
      repo = repository_context
      return nil unless repo && !repo.strip.empty?

      "Repository context:\n#{repo.strip}"
    end

    def safety_section
      "Safety:\n- Do not reveal secrets.\n- Follow applicable policies."
    end

    def execution_instructions
      return nil unless @execution

      if @execution.respond_to?(:instructions) && @execution.instructions
        @execution.instructions.to_s
      elsif @execution.respond_to?(:prompt) && @execution.prompt
        @execution.prompt.to_s
      end
    rescue StandardError => e
      Logging.warn("Failed to read execution instructions (#{e.class}: #{e.message})")
      nil
    end

    def repository_context
      path = data_file_path("repository.yml")
      data = Paths.load_data_file(path, default: {})
      return nil unless data.is_a?(Hash)

      summary = data["summary"].to_s.strip
      files = Array(data["files"]).map { |f| f.to_s.strip }.reject(&:empty?)

      parts = []
      parts << summary unless summary.empty?
      parts << files_section(files) unless files.empty?

      parts.join("\n")
    end

    def files_section(files)
      previews = files.map { |file| file_preview_block(file) }.compact
      return nil if previews.empty?

      (["Files:"] + previews).join("\n")
    end

    def file_preview_block(relative_path)
      return nil unless relative_path && !relative_path.empty?

      full_path = File.expand_path(relative_path, Dir.pwd)
      return nil unless File.file?(full_path)

      content = read_file_preview(full_path)
      return nil unless content

      [
        "- #{relative_path}",
        indent_lines(content, 2)
      ].join("\n")
    rescue StandardError => e
      Logging.warn("Failed to build file preview for #{relative_path} (#{e.class}: #{e.message})")
      nil
    end

    def read_file_preview(path)
      content = File.read(path, mode: "r:BOM|UTF-8")
      return content if content.length <= FILE_PREVIEW_SLICE_CHARS

      content[0, FILE_PREVIEW_SLICE_CHARS] + FILE_PREVIEW_TRUNCATION_SUFFIX
    rescue StandardError => e
      Logging.warn("Failed to read file: #{path} (#{e.class}: #{e.message})")
      nil
    end

    def indent_lines(text, spaces)
      pad = " " * spaces
      text.to_s.lines.map { |line| "#{pad}#{line}".rstrip }.join("\n")
    end

    def load_identity
      from_execution = identity_from_execution
      return from_execution if from_execution.is_a?(Hash)

      from_file = identity_from_file
      return from_file if from_file.is_a?(Hash)

      DEFAULT_IDENTITY.dup
    end

    def identity_from_execution
      return nil unless @execution
      return nil unless @execution.respond_to?(:metadata)

      meta = @execution.metadata
      return nil unless meta.is_a?(Hash)

      meta[IDENTITY_KEY]
    rescue StandardError => e
      Logging.warn("Failed to load identity from execution (#{e.class}: #{e.message})")
      nil
    end

    def identity_from_file
      path = data_file_path("identity.yml")
      data = Paths.load_data_file(path, default: {})
      return nil unless data.is_a?(Hash)

      data[IDENTITY_KEY] || data
    end

    def data_file_path(filename)
      return nil unless filename && !filename.strip.empty?

      if @execution&.respond_to?(:data_dir) && @execution.data_dir
        File.join(@execution.data_dir.to_s, filename)
      else
        File.join(Dir.pwd, "data", filename)
      end
    rescue StandardError => e
      Logging.warn("Failed to compute data file path for #{filename} (#{e.class}: #{e.message})")
      nil
    end
  end
end