# frozen_string_literal: true

require "yaml"
require "logger"

module Logging
  def self.logger
    @logger ||= Logger.new($stderr)
  end

  def self.warn(message)
    logger.warn(message)
  end

  def self.info(message)
    logger.info(message)
  end
end

module Paths
  def self.load_data_file(path)
    return {} unless path && File.file?(path)

    YAML.safe_load(File.read(path), permitted_classes: [], permitted_symbols: [], aliases: true) || {}
  rescue StandardError => e
    Logging.warn("Evolve — failed to load YAML at #{path}: #{e.class}: #{e.message}")
    {}
  end
end

module Evolve
  FIXED_CODE_KEY = "fixed_code"
  DEFAULT_SHELL_EXTENSIONS = %w[.sh .bash .zsh].freeze

  class Runner
    def initialize(scope:, output_dir:, data_file: nil, shell_extensions: DEFAULT_SHELL_EXTENSIONS)
      @scope = scope
      @output_dir = output_dir
      @data_file = data_file
      @shell_extensions = shell_extensions
    end

    def run(limit: 100)
      return if limit.to_i <= 0

      Logging.info("Starting “Evolve”…")

      settings = Paths.load_data_file(@data_file)
      improved_count = batch_improve(limit: limit.to_i, settings: settings)

      Logging.info("Done — improved #{improved_count} file(s)…")
      improved_count
    rescue StandardError => e
      Logging.warn("Evolve — run failed: #{e.class}: #{e.message}")
      nil
    end

    def batch_improve(limit:, settings:)
      records = fetch_targets(limit)
      return 0 if records.empty?

      records.sum do |target_record|
        improve_record(target_record, settings: settings) ? 1 : 0
      end
    rescue StandardError => e
      Logging.warn("Evolve — batch improve failed: #{e.class}: #{e.message}")
      nil
    end

    def improve_record(target_record, settings:)
      file_path = extract_path(target_record)
      return false unless file_path

      improve_path(file_path, settings: settings)
    rescue StandardError => e
      Logging.warn("Evolve — improve record failed: #{e.class}: #{e.message}")
      nil
    end

    def improve_path(file_path, settings:)
      return false unless File.file?(file_path)

      extension = File.extname(file_path).downcase
      result = if @shell_extensions.include?(extension)
        improve_shell_file(file_path, settings: settings)
      else
        improve_ruby_file(file_path, settings: settings)
      end

      return false unless result && result[FIXED_CODE_KEY].to_s != ""

      write_output(file_path, fixed_code: result[FIXED_CODE_KEY])
      true
    rescue StandardError => e
      Logging.warn("Evolve — improve path failed for #{file_path}: #{e.class}: #{e.message}")
      nil
    end

    def improve_ruby_file(file_path, settings:)
      source_code = File.read(file_path)
      prompt = build_prompt(source_code, settings: settings, file_path: file_path)

      response = call_model(prompt)
      response.is_a?(Hash) ? response : { FIXED_CODE_KEY => response.to_s }
    rescue StandardError => e
      Logging.warn("Evolve — Ruby improvement failed for #{file_path}: #{e.class}: #{e.message}")
      nil
    end

    def improve_shell_file(file_path, settings:)
      source_code = File.read(file_path)
      prompt = build_prompt(source_code, settings: settings, file_path: file_path, language: "shell")

      response = call_model(prompt)
      response.is_a?(Hash) ? response : { FIXED_CODE_KEY => response.to_s }
    rescue StandardError => e
      Logging.warn("Evolve — shell improvement failed for #{file_path}: #{e.class}: #{e.message}")
      nil
    end

    private

    def fetch_targets(limit)
      scope = @scope
      scope = scope.includes(:project) if scope.respond_to?(:includes)
      scope = scope.limit(limit) if scope.respond_to?(:limit)
      scope.to_a
    rescue StandardError => e
      Logging.warn("Evolve — failed to fetch targets: #{e.class}: #{e.message}")
      []
    end

    def extract_path(target_record)
      if target_record.respond_to?(:path) && target_record.path.to_s != ""
        target_record.path.to_s
      elsif target_record.respond_to?(:file_path) && target_record.file_path.to_s != ""
        target_record.file_path.to_s
      end
    end

    def build_prompt(source_code, settings:, file_path:, language: "ruby")
      rules = Array(settings["rules"]).join("\n").strip
      guidance = rules == "" ? "" : "\n\nRules:\n#{rules}"

      <<~PROMPT
        Improve this #{language} file — keep behavior, improve style and safety… Use “…” and “—” where appropriate in UI strings.

        Path: #{file_path}
        #{guidance}

        Return JSON with key “#{FIXED_CODE_KEY}”.

        Source:
        #{source_code}
      PROMPT
    end

    def write_output(original_path, fixed_code:)
      FileUtils.mkdir_p(@output_dir)
      output_path = File.join(@output_dir, File.basename(original_path))
      File.write(output_path, fixed_code)
      output_path
    rescue StandardError => e
      Logging.warn("Evolve — failed to write output for #{original_path}: #{e.class}: #{e.message}")
      nil
    end

    def call_model(prompt)
      return { FIXED_CODE_KEY => "" } unless prompt.to_s != ""

      { FIXED_CODE_KEY => prompt }
    rescue StandardError => e
      Logging.warn("Evolve — model call failed: #{e.class}: #{e.message}")
      nil
    end
  end
end