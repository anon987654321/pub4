# frozen_string_literal: true

require "open3"

module Analysis
  class Prescan
    GIT_TIMEOUT_SECONDS = 10
    STALE_DAYS_THRESHOLD = 30
    MAX_BRANCH_NAME_LENGTH = 80

    Result = Struct.new(
      :projects,
      :repositories,
      :git,
      :warnings,
      keyword_init: true
    )

    def initialize(projects_relation: Project.all, now: Time.current)
      @projects_relation = projects_relation
      @now = now
    end

    def call
      projects = load_projects
      repositories = load_repositories(projects)
      git = repositories.each_with_object({}) do |repository, memo|
        memo[repository.id] = git_status(repository.path)
      end

      Result.new(
        projects: projects,
        repositories: repositories,
        git: git,
        warnings: build_warnings(projects: projects, repositories: repositories, git: git)
      )
    end

    private

    attr_reader :projects_relation, :now

    def load_projects
      projects_relation
        .includes(:owner, :repository)
        .where(active: true)
        .to_a
    end

    def load_repositories(projects)
      repository_ids = projects.map(&:repository_id).compact
      return [] if repository_ids.empty?

      Repository
        .includes(:project)
        .where(id: repository_ids)
        .to_a
    end

    def build_warnings(projects:, repositories:, git:)
      warnings = []
      warnings.concat(stale_projects_warning(projects))
      warnings.concat(missing_repo_warning(repositories))
      warnings.concat(dirty_worktree_warning(repositories, git))
      warnings
    end

    def stale_projects_warning(projects)
      cutoff = now - STALE_DAYS_THRESHOLD.days
      stale_ids = Project.where(id: projects.map(&:id)).where("updated_at < ?", cutoff).pluck(:id)

      return [] if stale_ids.empty?

      [{ type: :stale_projects, project_ids: stale_ids, cutoff: cutoff }]
    end

    def missing_repo_warning(repositories)
      missing_ids = repositories.select { |repository| repository.path.blank? }.map(&:id)
      return [] if missing_ids.empty?

      [{ type: :missing_repository_path, repository_ids: missing_ids }]
    end

    def dirty_worktree_warning(repositories, git)
      dirty_ids = repositories.filter_map do |repository|
        status = git[repository.id]
        repository.id if status[:ok] && status[:dirty]
      end

      return [] if dirty_ids.empty?

      [{ type: :dirty_worktree, repository_ids: dirty_ids }]
    end

    def git_status(repo_path)
      return { ok: false, error: :missing_path } if repo_path.to_s.strip.empty?

      stdout, stderr, status = run_git_status(repo_path)
      return { ok: false, error: :command_failed, stderr: stderr.to_s.strip } unless status&.success?

      porcelain = stdout.to_s.lines.map(&:strip).reject(&:empty?)
      branches = extract_branches(repo_path)

      {
        ok: true,
        dirty: porcelain.any?,
        changes: porcelain,
        branches: branches
      }
    end

    def run_git_status(repo_path)
      Open3.capture3(
        "git",
        "-C",
        repo_path,
        "status",
        "--porcelain",
        timeout: GIT_TIMEOUT_SECONDS
      )
    rescue StandardError => error
      ["", error.message, nil]
    end

    def extract_branches(repo_path)
      stdout, _stderr, status = Open3.capture3(
        "git",
        "-C",
        repo_path,
        "branch",
        "--format=%(refname:short)",
        timeout: GIT_TIMEOUT_SECONDS
      )

      return [] unless status&.success?

      stdout
        .to_s
        .lines
        .map { |line| line.strip.first(MAX_BRANCH_NAME_LENGTH) }
        .reject(&:empty?)
    rescue StandardError
      []
    end
  end
end