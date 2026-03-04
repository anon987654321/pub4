# frozen_string_literal: true

require "open3"

module Analysis
  class Prescan
    SEPARATOR = "\",\n        \""
    LS_FILES_CMD = %w[git ls-files].freeze

    def initialize(repo_path:, repo_model: Repository, file_model: RepoFile, runner: Open3)
      @repo_path = repo_path
      @repo_model = repo_model
      @file_model = file_model
      @runner = runner
    end

    def call
      normalized_path = normalize_repo_path(@repo_path)
      return [] if normalized_path.nil?

      repo = load_repo(normalized_path)
      return [] unless repo

      paths = file_list(normalized_path)
      return [] if paths.empty?

      upsert_files(repo, paths)
    end

    def normalize_repo_path(path)
      value = path.to_s.strip
      return nil if value.empty?

      value
    end

    def load_repo(path)
      @repo_model.includes(:project).find_by(path:)
    end

    def file_list(path)
      stdout = run_cmd(LS_FILES_CMD, chdir: path)
      parse_stdout_lines(stdout)
    end

    def parse_stdout_lines(stdout)
      stdout.to_s.lines.map { |l| l.to_s.strip }.reject(&:empty?)
    end

    def upsert_files(repo, paths)
      existing = existing_paths(repo, paths)
      missing = paths - existing
      return existing if missing.empty?

      rows = missing.map { |p| { repository_id: repo.id, path: p } }
      @file_model.insert_all(rows) # rubocop:disable Rails/SkipsModelValidations
      existing + missing
    end

    def existing_paths(repo, paths)
      @file_model.where(repository_id: repo.id, path: paths).pluck(:path)
    end

    def run_cmd(cmd, chdir:)
      stdout, _stderr, status = @runner.capture3(*cmd, chdir: chdir)
      return stdout if status.success?

      ""
    rescue SystemCallError
      ""
    end

    private :normalize_repo_path,
            :load_repo,
            :file_list,
            :parse_stdout_lines,
            :upsert_files,
            :existing_paths,
            :run_cmd
  end
end