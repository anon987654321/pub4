# frozen_string_literal: true

require_relative "test_helper"

class TestDependencyContracts < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_reek_dependency_is_declared_for_reek_rule
    gemfile = File.read(File.join(ROOT, "Gemfile"))
    lockfile = File.read(File.join(ROOT, "Gemfile.lock"))

    assert_includes gemfile, 'gem "reek", "~> 6.4", require: false'
    assert_match(/^    reek \(/, lockfile)
    assert_match(/^  reek \(~> 6\.4\)/, lockfile)
  end

  def test_prism_dependency_matches_ruby_language_support
    require "prism"

    rules = Master.load_yaml(File.join(ROOT, "data", "rules.yml"))
    ruby_version = rules.dig("languages", "ruby", "version")

    assert_equal "3.3+", ruby_version
    assert_operator Gem::Version.new(Prism::VERSION), :>=, Gem::Version.new("1.7.0")
  end

  REPO = File.expand_path("../..", __dir__)

  # No workflow may name a Ruby version. `.ruby-version` is the pin — five files,
  # all 3.4.9, one per tree — and a workflow that restates it is a second source
  # that drifts silently: two workflows once installed 3.3 against a repo pinned
  # at 3.4.9, so they tested an interpreter nobody runs locally or on vm23.
  #
  # setup-ruby resolves `.ruby-version` against the step's working directory, and
  # each of those directories has one, so this reads the same pin everywhere.
  def test_no_workflow_hardcodes_a_ruby_version
    offenders = Dir[File.join(REPO, ".github/workflows/*.yml")].filter_map do |path|
      literal = File.read(path)[/^\s*ruby-version:\s*["']?(\d[\d.]*)["']?\s*$/, 1]
      "#{File.basename(path)} pins #{literal}" if literal
    end

    assert_empty offenders, "workflows must read .ruby-version, not restate it"
  end

  # A step that fails must fail the job. A self-improvement workflow ran
  # `bundle` at the repo root, where no Gemfile exists, and called an
  # `exe/master` that was never there; `continue-on-error` on the steps that
  # mattered meant nothing reported it. So: no step may swallow its exit, and a
  # step that runs bundle must run where a Gemfile is.
  def test_every_workflow_step_can_fail_and_bundles_where_a_gemfile_is
    require "yaml"
    problems = Dir[File.join(REPO, ".github/workflows/*.yml")].sort.flat_map do |path|
      name = File.basename(path)
      YAML.safe_load_file(path, aliases: true).fetch("jobs").flat_map do |job_id, job|
        workflow_step_problems(name, job_id, job)
      end
    end

    assert_empty problems, problems.join("\n")
  end

  def test_every_ruby_version_file_agrees
    pins = Dir[File.join(REPO, "{,MASTER/,RAILS/*/}.ruby-version")].to_h do |path|
      [path.sub("#{REPO}/", ""), File.read(path).strip]
    end

    refute_empty pins, "no .ruby-version found — this test would pass having measured nothing"
    assert_equal 1, pins.values.uniq.size, "the pin disagrees with itself: #{pins.inspect}"
  end

  private

  def workflow_step_problems(name, job_id, job)
    default_dir = job.dig("defaults", "run", "working-directory") || "."
    matrix_apps = Array(job.dig("strategy", "matrix", "app"))
    Array(job["steps"]).flat_map do |step|
      next [] unless step["run"]

      label = "#{name} #{job_id} #{step['name'] || step['run'].lines.first.strip}"
      found = []
      found << "#{label}: continue-on-error swallows the exit" if step["continue-on-error"]
      found << "#{label}: `|| true` swallows the exit" if step["run"].include?("|| true")
      if step["run"].match?(/\bbundle\b/)
        dir = step["working-directory"] || default_dir
        dirs = dir.include?("${{ matrix.app }}") ? matrix_apps.map { |app| dir.gsub("${{ matrix.app }}", app) } : [dir]
        dirs.reject { |each| File.file?(File.join(REPO, each, "Gemfile")) }.each do |missing|
          found << "#{label}: runs bundle in #{missing}, which has no Gemfile"
        end
      end
      found
    end
  end
end
