# frozen_string_literal: true

require "fileutils"
require "pathname"

module FileProcessing
  CHANGE_APPEND = "\")\n          changes << \""
  CHANGE_JOIN = "\",\n          \""
  MAX_RENAME_ATTEMPTS = 10
  VALID_EXTENSIONS = %w[.pdf .txt .md .csv .json .xml .jpg .jpeg .png].freeze

  Result = Struct.new(
    :directory,
    :assessments,
    :renames,
    :transformations,
    :deletions,
    :errors,
    keyword_init: true
  )

  class FileProcessor
    def initialize(directory_path:, records_scope: nil, transformer: nil)
      @directory = Pathname.new(directory_path)
      @records_scope = records_scope
      @transformer = transformer
    end

    def transform_directory
      return empty_result unless directory.exist?

      payload = {
        directory: directory.to_s,
        assessments: [],
        renames: [],
        transformations: [],
        deletions: [],
        errors: []
      }

      payload[:assessments] = phase_assess
      payload[:deletions] = phase_clean
      payload[:renames] = phase_rename
      payload[:transformations] = phase_transform

      Result.new(**payload)
    end

    def phase_assess
      files = discover_files(directory)
      files.map { |path| assess_file(path) }.compact
    end

    def phase_clean
      files = discover_files(directory)
      files.filter_map { |path| delete_if_invalid(path) }
    end

    def phase_rename
      files = discover_files(directory)
      files.filter_map { |path| rename_if_needed(path) }
    end

    def phase_transform
      return [] unless transformer

      files = discover_files(directory)
      files.filter_map { |path| transform_file(path) }
    end

    private

    attr_reader :directory, :records_scope, :transformer

    def empty_result
      Result.new(
        directory: directory.to_s,
        assessments: [],
        renames: [],
        transformations: [],
        deletions: [],
        errors: []
      )
    end

    def discover_files(root)
      return [] unless root.directory?

      root.children.flat_map do |entry|
        entry.directory? ? discover_files(entry) : [entry]
      end
    end

    def assess_file(path)
      return unless path.file?

      {
        path: path.to_s,
        size: path.size,
        ext: path.extname.downcase,
        valid_extension: valid_extension?(path),
        has_records: associated_records_for(path).any?
      }
    rescue StandardError => e
      record_error("assess", path, e)
      nil
    end

    def delete_if_invalid(path)
      return unless path.file?
      return if valid_extension?(path)

      FileUtils.rm_f(path.to_s)
      { action: "deleted", path: path.to_s, reason: "invalid_extension" }
    rescue StandardError => e
      record_error("clean", path, e)
      nil
    end

    def rename_if_needed(path)
      return unless path.file?

      normalized = normalize_filename(path.basename.to_s)
      return if normalized == path.basename.to_s

      target = unique_target_path(path, normalized)
      FileUtils.mv(path.to_s, target.to_s)

      { action: "renamed", from: path.to_s, to: target.to_s }
    rescue StandardError => e
      record_error("rename", path, e)
      nil
    end

    def transform_file(path)
      return unless path.file?
      return unless valid_extension?(path)

      output_path = transformer.call(path)
      return unless output_path

      { action: "transformed", from: path.to_s, to: output_path.to_s }
    rescue StandardError => e
      record_error("transform", path, e)
      nil
    end

    def normalize_filename(filename)
      filename
        .strip
        .gsub(/\s+/, "_")
        .gsub(/[^\w.\-]/, "")
    end

    def unique_target_path(source_path, desired_basename)
      base = source_path.dirname.join(desired_basename)
      return base unless base.exist?

      stem = File.basename(desired_basename, ".*")
      ext = File.extname(desired_basename)

      1.upto(MAX_RENAME_ATTEMPTS) do |suffix|
        candidate = source_path.dirname.join("#{stem}_#{suffix}#{ext}")
        return candidate unless candidate.exist?
      end

      source_path.dirname.join("#{stem}_#{Time.now.to_i}#{ext}")
    end

    def valid_extension?(path)
      VALID_EXTENSIONS.include?(path.extname.downcase)
    end

    def associated_records_for(path)
      return [] unless records_scope

      # Prevent N+1 when callers pass ActiveRecord relations that will be enumerated.
      scope = records_scope
      scope = scope.includes(:attachments) if scope.respond_to?(:includes)

      file_key = path.basename.to_s
      scope.respond_to?(:where) ? scope.where(file_name: file_key) : []
    end

    def record_error(phase, path, error)
      @errors ||= []
      @errors << { phase: phase, path: path.to_s, error: error.class.name, message: error.message }
    end

    def change_lines(segments)
      segments.join(CHANGE_JOIN)
    end
  end
end