# frozen_string_literal: true

require_relative "test_helper"

# Regressions from the 2026-07-26 audit backlog: three commands that raised or
# returned nothing the moment anyone ran them, all of them shipped and none of
# them covered. Each test here pins the specific failure, not the general shape.
class TestModeAndOrders < Minitest::Test
  Registry = Master::CLI::CommandRegistry

  # `/mode` and `/reasoning` were both named `dispatch_mode` inside
  # Master::CLI::CommandRegistry. command_registry.rb requires work_commands.rb
  # first, so its own definition loaded last and won, while work_commands' table
  # entry won the "mode" key — so every `/mode` form arrived at a method
  # expecting a Config holding a String root, and died on `config.reasoning_mode`.
  def test_mode_reports_the_session_posture
    Dir.mktmpdir do |root|
      out = Registry.dispatch_mode(root:, ctx: { args: "" })
      assert_match(/\Amode=(loose|balanced|strict) profile=\S+ council=\S+ fix_passes=\d+\z/, out)
    end
  end

  # `/mode list` returned one blank line per mode: the map block at
  # work_commands.rb had an empty body.
  def test_mode_list_describes_every_posture
    Dir.mktmpdir do |root|
      lines = Registry.dispatch_mode(root:, ctx: { args: "list" }).lines(chomp: true)

      assert_equal Master::Ground::ModePosture::MODES.size, lines.size
      refute(lines.any? { |line| line.strip.empty? }, "every mode needs a rendered line")
      Master::Ground::ModePosture::MODES.each_with_index do |mode, i|
        assert_includes lines[i], "mode=#{mode}"
        assert_includes lines[i], "fix_passes="
        assert_match(/—\s+\S/, lines[i], "each mode line carries its description")
      end
      assert_equal 1, lines.count { |line| line.start_with?("*") }, "exactly one active marker"
    end
  end

  def test_mode_switches_posture_and_rejects_unknown_ones
    Dir.mktmpdir do |root|
      assert_includes Registry.dispatch_mode(root:, ctx: { args: "strict" }), "mode=strict"
      assert_includes Registry.dispatch_mode(root:, ctx: { args: "sideways" }), "unknown mode"
    ensure
      ENV.delete("MASTER_MODE")
    end
  end

  # The reasoning-mode command kept its behaviour under its own name.
  def test_reasoning_reports_and_sets_the_prompt_strategy
    config = FakeConfig.new
    assert_includes Registry.dispatch_reasoning(config, ctx: { args: "" }), "reasoning: direct"

    assert_equal "reasoning: react", Registry.dispatch_reasoning(config, ctx: { args: "react" })
    assert_equal "react", config["reasoning_mode"]
    assert config.saved?
  end

  # The root cause was two same-named methods in one module, which Ruby resolves
  # silently. Nothing else in the command surface may repeat it.
  def test_no_dispatch_method_is_defined_twice_across_the_command_modules
    root = File.expand_path("../lib/cli", __dir__)
    owners = Hash.new { |h, k| h[k] = [] }
    paths = [File.join(root, "command_registry.rb")] + Dir.glob(File.join(root, "command_registry", "*.rb"))
    paths.each do |path|
      source = File.read(path)
      next unless source.include?("module CommandRegistry")

      source.scan(/^\s*def (dispatch_\w+)/) { |(name)| owners[name] << File.basename(path) }
    end

    refute_empty owners, "expected to find dispatch_* methods to check"
    duplicated = owners.select { |_, files| files.size > 1 }
    assert_empty duplicated, "same dispatch name defined in two files; the later load silently wins: #{duplicated}"
  end

  def test_every_bootstrap_docs_section_resolves
    keys = Master::Ground::BootstrapDocs.keys - ["bootstrap"]
    refute_empty keys
    keys.each do |topic|
      body = Master::Ground::BootstrapDocs.section(topic)
      refute_nil body, "BootstrapDocs #{topic} is empty"
      refute_includes body.to_s, "/orient #{topic}",
                      "BootstrapDocs #{topic} answers by naming a removed /orient command"
    end
  end

  def test_bootstrap_indexes_every_other_section
    index = Master::Ground::BootstrapDocs.section("bootstrap")

    (Master::Ground::BootstrapDocs.keys - ["bootstrap"]).each do |key|
      assert_includes index, key
    end
  end

  # Ground::Orders::Backup existed, was reachable by no key, and pointed three
  # directories above MASTER instead of one.
  def test_backup_order_is_registered
    assert_equal Master::Ground::Orders::Backup, Master::Ground::Orders::Registry.lookup("backup")
  end

  def test_every_declared_callable_resolves_to_a_class
    orders = Master.load_yaml(Master.state_path)
    keys = Array(orders).filter_map { |order| order["callable"] if order.is_a?(Hash) }

    refute_empty keys
    keys.each do |key|
      refute_nil Master::Ground::Orders::Registry.lookup(key),
                 "data/state.yml declares callable: #{key} with no Registry entry"
    end
  end

  def test_backup_source_is_the_repo_root_not_its_grandparent
    Dir.mktmpdir do |repo|
      master = File.join(repo, "MASTER")
      FileUtils.mkdir_p(master)
      order = Master::Ground::Orders::Backup.new(container: { root: master })

      assert_equal File.realpath(repo), File.realpath(order.source_root)
    end
  end

  class FakeConfig
    def initialize = @values = { "reasoning_mode" => "direct" }

    def []=(key, value)
      @values[key] = value
    end

    def [](key) = @values[key]
    def reasoning_mode = @values["reasoning_mode"]
    def save! = @saved = true
    def saved? = @saved == true
  end
end
