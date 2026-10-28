# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "rbconfig"

class CheckContractSpec < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  # The ladder bin/check --ladder loads.
  CHECK = File.join(ROOT, "lib", "operator", "check_ladder.rb")

  # The command reaches bin/master on stdin, and the check does not wait forever for
  # an answer.
  #
  # Two properties, not one spelling: something is written to the child's
  # stdin, and there is a wall clock on the wait. A stage that hangs is
  # the one failure INCONCLUSIVE cannot catch, because every pattern in that
  # list is something a stage says on its way out.
  def test_check_runs_master_cli
    source = File.read(CHECK)
    assert_includes source, 'File.join(ROOT, "bin", "master")'
    assert_match(/stdin_data|stdin\.puts/, source,
                 "bin/check --ladder must feed the command to bin/master on stdin")
    assert_includes source, "STAGE_TIMEOUT",
                    "bin/check --ladder must bound how long it waits for a stage; a stage that never " \
                    "returns produces no output for INCONCLUSIVE to match on"
  end

  # One boot per tier per tree, because one boot does the whole tier: /scan
  # already scans, fixes and re-scans, and /critique and /review both name the
  # critique stage, so repeating either reruns the whole sequence.
  #
  # Asserted on the shape rather than the literal line, since the flag spellings
  # move: what must hold is that no tier repeats a stage.
  def test_each_tier_boots_the_runtime_once_per_tree
    source = File.read(CHECK)
    lexical = source[/lexical = SCAN_ONLY \? (.*?) : (.*?)$/, 2].to_s
    semantic = source[/^  semantic = (.*?)$/, 1].to_s

    assert_equal 1, lexical.scan(%r{/\w+}).size,
                 "the lexical tier boots bin/master once: /scan already fixes and re-scans"
    assert_equal 1, semantic.scan(%r{/\w+}).size,
                 "/critique and /review name one stage; running both runs the council twice"
  end

  # The chain ends with a clean tree, and that tree is MASTER plus whatever
  # --tree named.
  def test_check_is_expected_to_keep_repo_clean
    source = File.read(CHECK)
    assert_includes source, "assert_clean(*ASSERT_PATHS)"
    assert_includes source, %q{ASSERT_PATHS = (SELECTED_TREES | ["MASTER"])}
  end

  # The check must cover every sibling tree CLAUDE.md names, not a subset.
  #
  # Read out of `--explain` rather than out of the source, because the target
  # list is computed: --tree narrows it, and a spec grepping for a literal
  # `deploy: %w[...]` measures a spelling that flag removed. --explain prints the
  # ladder and runs nothing, so this is the check's own answer to what it scans.
  def test_check_targets_every_sibling_tree
    explain = check_explain

    %w[../RAILS ../OPENBSD].each do |tree|
      assert_includes explain, tree,
                      "bin/check --ladder does not scan #{tree}; a check whose target list is shorter " \
                      "than the repo reports clean on the part it looked at"
    end
  end

  # Every path the ladder names must exist; a stale entry means the check
  # /scans a directory that is not there.
  def test_check_deploy_paths_exist
    # Any flags, not one named flag, so a new flag is never read as a directory.
    paths = check_explain.scan(%r{bin/master /\w+((?:\s+--[\w-]+)*)\s+(\S+)}).map(&:last).uniq

    assert_operator paths.size, :>=, 4, "expected the default ladder to name all four trees"
    paths.each do |relative|
      absolute = File.expand_path(relative, ROOT)
      assert File.directory?(absolute), "bin/check --ladder references missing directory: #{relative}"
    end
  end

  def test_dogfood_uses_the_shared_runtime_selection
    source = File.read(File.join(ROOT, "bin", "dogfood"))

    assert_includes source, 'require_relative "../lib/operator/ruby_runner"'
    assert_includes source, "RUBY = Operator::RubyRunner.ruby_cmd"
    assert_includes source, "Operator::RubyRunner.bundle_cmd"
    refute_includes source, "RbConfig.ruby"
    refute_includes source, "RUBY_PLATFORM.include?(\"openbsd\")"
  end

  def test_ruby_runtime_contract_allows_openbsd_packages
    environment = File.read(File.join(ROOT, "lib", "operator", "environment.rb"))
    deploy_environment = File.read(File.join(ROOT, "../OPENBSD/lib", "environment.rb"))
    entrypoint = File.read(File.join(ROOT, "lib", "boot", "entrypoint.rb"))
    wrapper = File.read(File.join(ROOT, "bin", "ruby"))
    gemfile = File.read(File.join(ROOT, "Gemfile"))

    assert_includes environment, 'SUPPORTED_RUBY_MIN = Gem::Version.new("3.3.0")'
    assert_includes environment, 'SUPPORTED_RUBY_MAX = Gem::Version.new("4.1.0")'
    assert_includes deploy_environment, 'OPENBSD_RUBY_PATTERN = /\A3\.(?:3|4)\.\d+\z/'
    assert_includes entrypoint, "Operator::RubyRunner.best_available_ruby"
    assert_includes wrapper, "ruby34"
    assert_includes wrapper, "ruby33"
    assert_includes gemfile, 'ruby ">= 3.3", "< 4.1"'
  end

  def test_ruby_runner_openbsd_method_is_real_ruby_source
    source = File.read(File.join(ROOT, "lib", "operator", "ruby_runner.rb"))

    assert_includes source, "def openbsd_path(name, root: Environment.repo_root)"
    refute_includes source, "def openbsd_path(name, root: Environment.repo_root)\\n"
  end

  def test_check_uses_the_shared_runtime_selection
    source = File.read(CHECK)

    assert_includes source, "require_relative \"ruby_runner\""
    assert_includes source, "Operator::RubyRunner.ruby_cmd"
    assert_includes source, "Operator::RubyRunner.bundle_cmd"
    assert_includes source, "Open3.popen2e(SAFE_ENV, File.join(ROOT, \"bin\", \"master\"), chdir: REPO)"
  end

  def test_operator_app_suites_use_the_shared_runtime
    source = File.read(File.join(ROOT, "bin", "operator"))

    assert_includes source, 'require "operator/ruby_runner"'
    assert_includes source, "[BUNDLE, \"exec\", RUBY, \"bin/rails\", \"test\"]"
    refute_includes source, "%w[rbenv exec bundle exec bin/rails test]"
    refute_includes source, "RBENV_VERSION"
  end

  def test_check_forces_safe_env
    source = File.read(CHECK)
    assert_includes source, "SAFE_ENV"
    assert_includes source, '"MASTER_SAFE_MODE" => "1"'
    assert_includes source, '"MASTER_AUTOFIX" => "0"'
    assert_includes source, '"MASTER_WATCH" => "0"'
    assert_includes source, '"MASTER_WATCHER" => "0"'
    assert_includes source, '"MASTER_HEARTBEAT" => "0"'
  end

  # The assertions above are string matches; a key can be present and still not
  # be the one MechanicalAutofix reads. So this one asks the consumer instead of
  # the spelling.
  def test_check_safe_env_actually_disables_scan_autofix
    require_relative "../lib/fix/scan/mechanical_autofix"

    env = safe_env_from_source
    assert_includes env.keys, "MASTER_SCAN_AUTOFIX",
                    "bin/check --ladder's SAFE_ENV must name the variable /scan's autofix pass actually reads"
    refute Master::Fix::Scan::MechanicalAutofix.enabled?(env:),
           "bin/check --ladder's SAFE_ENV does not disable MechanicalAutofix, so the full chain's first " \
           "/scan writes to the tree before /fix runs -- which is what the COMMANDS comment " \
           "promises it does not do"
  end

  # Parsed out of the source rather than required, because bin/check --ladder runs the
  # whole chain at load time; there is nothing to require without running it.
  def safe_env_from_source
    body = File.read(CHECK)[/SAFE_ENV = \{(.*?)\}\.freeze/m, 1].to_s
    body.scan(/"([A-Z_]+)"\s*=>\s*"([^"]*)"/).to_h
  end

  def test_web_command_palette_matches_the_slash_surface
    require_relative "../lib/cli/command_registry/help"
    surface = Master::CLI::CommandRegistry.command_surface
    view = File.read(File.expand_path("../../RAILS/master/app/views/chat/index.html.erb", __dir__))
    chat = File.read(File.expand_path("../../RAILS/master/public/chat.js", __dir__))

    assert_includes view, "window.MASTER_COMMANDS"
    assert_includes view, "CommandRegistry.command_surface"
    assert_equal Master::CLI::CommandRegistry.slash_commands.sort, surface.map { |row| row.fetch(:cmd) }.sort
    assert_includes chat, "(window.MASTER_COMMANDS || [])"
    assert_includes chat, "fetch('/chat/skills')"
    assert_includes chat, "{ cmd: 'ping', hint: 'smoke test connection', category: 'health' }"
    refute_includes chat, "const COMMANDS = ["
  end

  # The ladder, without running it. Cached because both tests read the same
  # answer and the script boots a bare ruby to print it.
  def self.check_explain
    @check_explain ||= begin
      out, status = Open3.capture2e(RbConfig.ruby, CHECK, "--explain", chdir: ROOT)
      raise "bin/check --explain failed: #{out}" unless status.success?

      out
    end
  end

  private

  def check_explain = self.class.check_explain
end
