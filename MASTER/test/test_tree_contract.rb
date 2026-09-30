# frozen_string_literal: true

require "minitest/autorun"

class TreeContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  BOOT_FILES = %w[
    bin/ruby
    bin/cli
    lib/boot/entrypoint.rb
    lib/boot/dependency_manager.rb
    lib/master.rb
    data/soul.yml
    data/rules.yml
  ].freeze

  FORBIDDEN_RELOCATIONS = {
    "MASTER/bin/ruby" => "MASTER/bin/ruby",
    "MASTER/bin/cli" => "MASTER/bin/cli",
    "MASTER/lib" => "MASTER/lib",
    "MASTER/data" => "MASTER/data",
    "MASTER/law" => "MASTER/law",
  }.freeze

  def test_boot_spine_exists_in_its_canonical_locations
    BOOT_FILES.each do |relative|
      assert File.file?(File.join(ROOT, relative)), "missing boot-critical path: #{relative}"
    end
  end

  def test_boot_spine_uses_relative_lib_loader
    cli = File.read(File.join(ROOT, "bin/cli"), encoding: "UTF-8")
    entrypoint = File.read(File.join(ROOT, "lib/boot/entrypoint.rb"), encoding: "UTF-8")

    assert_includes cli, 'require_relative "../lib/boot/entrypoint"'
    assert_includes cli, '$LOAD_PATH.unshift File.expand_path("../lib", __dir__)'
    assert_includes entrypoint, 'require_relative "dependency_manager"'
    assert_includes entrypoint, 'File.join(root, "bin", "ruby")'
  end

  def test_protected_master_boundaries_remain_directories
    FORBIDDEN_RELOCATIONS.values.uniq.each do |relative|
      assert Dir.exist?(File.join(ROOT, relative)), "protected MASTER boundary moved: #{relative}"
    end
  end
end
