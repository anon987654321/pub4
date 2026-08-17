# frozen_string_literal: true

require "minitest/autorun"
require "yaml"

# RAILS/bin/premerge exists because neither workflow runs on push — both are
# workflow_dispatch only, and both say why in their own header: a GitHub billing
# lock. A local stand-in for CI is worth exactly as much as its agreement with
# the thing it stands in for, so this asserts that agreement rather than trusting
# it.
#
# The failure this prevents is specific and quiet: a workflow gains a step, the
# local command does not, and it keeps reporting green over a smaller check than
# the name implies. That is the same shape as the four gates found measuring
# nothing this week, and the same shape as a browser gate passing without a
# browser.
class PremergeMirrorsCiTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  REPO = File.expand_path("..", ROOT)
  PREMERGE = File.join(ROOT, "bin", "premerge")

  def workflow(name) = YAML.safe_load_file(File.join(REPO, ".github", "workflows", name), aliases: true)

  def premerge_source = @premerge_source ||= File.read(PREMERGE)

  def test_premerge_exists_and_is_executable
    assert File.file?(PREMERGE), "RAILS/bin/premerge is missing"
    assert File.executable?(PREMERGE), "RAILS/bin/premerge must be executable"
  end

  # Every app the Rails workflow builds a matrix over must be a step here.
  def test_it_covers_every_app_the_rails_workflow_runs
    matrix = workflow("rails-tests.yml").dig("jobs", "test", "strategy", "matrix", "app")

    refute_nil matrix, "rails-tests.yml no longer declares an app matrix"
    matrix.each do |app|
      assert_match(/APPS = %w\[[^\]]*\b#{app}\b/, premerge_source,
                   "rails-tests.yml runs #{app} and premerge does not")
    end
  end

  def test_it_runs_the_same_command_the_rails_workflow_runs
    run = workflow("rails-tests.yml").dig("jobs", "test", "steps").filter_map { |s| s["run"] }.join("\n")

    assert_includes run, "bin/ci", "the workflow stopped running bin/ci"
    assert_includes premerge_source, %("bundle", "exec", "bin/ci")
  end

  def test_it_runs_the_layout_suite_the_way_the_workflow_does
    job = workflow("layout-suite.yml").dig("jobs", "layout_suite")
    step = job.fetch("steps").find { |s| s["run"].to_s.include?("runner.rb") }

    refute_nil step, "layout-suite.yml no longer runs the gate runner"
    assert_includes step["run"], "layout_suite"
    assert_includes premerge_source, "layout_suite"

    # A pre-merge check that repairs the tree while measuring it is measuring a
    # tree that does not exist yet. The workflow sets this and so must premerge.
    assert_equal "0", step.dig("env", "GATE_AUTOFIX").to_s
    assert_includes premerge_source, %("GATE_AUTOFIX" => "0")
  end

  def test_it_keeps_the_apps_yml_inventory_check
    inventory = workflow("layout-suite.yml").dig("jobs", "inventory", "steps").filter_map { |s| s["run"] }.join("\n")

    %w[port deploy_script].each do |field|
      assert_includes inventory, field
      assert_includes premerge_source, field
    end
    assert_includes inventory, "duplicate ports"
    assert_includes premerge_source, "duplicate ports"
  end

  # The whole point of the exit codes. A step that could not run has measured
  # nothing, and 0 would claim otherwise.
  def test_a_step_that_cannot_run_exits_three_rather_than_zero
    assert_includes premerge_source, "exit 3"
    assert_match(/BLOCKED/, premerge_source)
  end

  # If a workflow starts running on push again, this command stops being the
  # only line of defence — and this test should be the thing that says so.
  def test_it_records_that_the_workflows_are_still_manual
    %w[rails-tests.yml layout-suite.yml].each do |name|
      # YAML 1.1 reads a bare `on:` as the boolean true, so the key is not the
      # string "on". Fetching "on" raises KeyError and the test would read as a
      # broken workflow rather than a mis-keyed lookup.
      triggers = workflow(name)[true] || workflow(name)["on"]
      next unless triggers.is_a?(Hash)

      assert_equal ["workflow_dispatch"], triggers.keys,
                   "#{name} runs automatically again — premerge is no longer the only gate, " \
                   "and its header comment should stop saying it is"
    end
  end
end
