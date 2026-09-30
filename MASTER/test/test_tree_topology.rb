# frozen_string_literal: true

require "minitest/autorun"
require "yaml"

class TreeTopologyTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  BOOT_FILES = %w[
    bin/ruby
    bin/cli
    lib/master.rb
    lib/boot/entrypoint.rb
    data/rules.yml
    data/autoload.yml
  ].freeze

  ZEITWERK_DIRECTORIES = %w[
    lib/ai
    lib/cli/command_registry
    lib/cli/session
    lib/review/scan/rules
    lib/review/scan/engines
    lib/fix/fix_loop
    lib/core/memory
    lib/music
    lib/voice/renderer
  ].freeze

  def test_boot_files_remain_at_canonical_paths
    BOOT_FILES.each do |relative|
      assert File.file?(File.join(ROOT, relative)), "missing boot contract file: #{relative}"
    end
  end

  def test_cli_still_boots_from_master_directory
    cli = File.read(File.join(ROOT, "bin/cli"), encoding: "UTF-8")
    assert_includes cli, 'require_relative "../lib/boot/entrypoint"'
    assert_includes cli, 'Dir.chdir(File.expand_path("..", __dir__))'
    assert_includes cli, 'require "master"'
  end

  def test_master_keeps_explicit_operator_contract_path
    master = File.read(File.join(ROOT, "lib/master.rb"), encoding: "UTF-8")
    assert_includes master, 'require_relative "ai/operator_contract"'
    assert File.file?(File.join(ROOT, "lib/ai/operator_contract.rb"))
  end

  def test_zeitwerk_namespace_directories_remain_intact
    ZEITWERK_DIRECTORIES.each do |relative|
      assert Dir.exist?(File.join(ROOT, relative)), "Zeitwerk namespace directory moved or flattened: #{relative}"
    end
  end

  def test_autoload_manifest_contains_only_real_paths
    manifest = YAML.safe_load_file(File.join(ROOT, "data/autoload.yml")).fetch("autoload")
    manifest.values.flatten.each do |relative|
      assert File.file?(File.join(ROOT, "lib", relative)), "autoload ignore points at missing file: #{relative}"
    end
  end
end
