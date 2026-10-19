# frozen_string_literal: true

require "minitest/autorun"
require "fileutils"
require "pathname"
require "tmpdir"

# This contract runs without booting Rails. before_initialize executes immediately
# in the small host below, so the real initializer is exercised against a temp tree.
module Rails
  class ContractConfig
    def before_initialize(&block) = block.call
  end

  class << self
    attr_accessor :contract_root

    def root = contract_root
    def application = (@application ||= Struct.new(:config).new(ContractConfig.new))
  end
end

class PropshaftSafetyContractTest < Minitest::Test
  REPO_ROOT = File.expand_path("../..", __dir__)
  INITIALIZER = File.join(REPO_ROOT, "RAILS", "master", "config", "initializers", "propshaft_safety.rb")

  def load_initializer(root)
    Rails.contract_root = Pathname.new(root)
    load INITIALIZER
  end

  def test_recursive_asset_cleanup_requires_a_real_directory
    source = File.read(INITIALIZER)

    assert_includes source, "File.symlink?(nested)"
    assert_includes source, "nested.directory?"
    assert_includes source, "FileUtils.rm_rf(nested)"
  end

  def test_symlinked_asset_target_is_refused_without_touching_target
    Dir.mktmpdir("propshaft-app-") do |app_root|
      Dir.mktmpdir("propshaft-external-") do |external_root|
        assets = File.join(app_root, "public", "assets")
        FileUtils.mkdir_p(assets)
        marker = File.join(external_root, "keep.txt")
        File.write(marker, "keep")
        File.symlink(external_root, File.join(assets, "assets"))

        error = assert_raises(RuntimeError) { load_initializer(app_root) }

        assert_match(/refusing symlinked digest output/, error.message)
        assert_equal "keep", File.read(marker)
      end
    end
  end

  def test_non_directory_asset_target_is_refused
    Dir.mktmpdir("propshaft-app-") do |app_root|
      assets = File.join(app_root, "public", "assets")
      FileUtils.mkdir_p(assets)
      path = File.join(assets, "assets")
      File.write(path, "keep")

      error = assert_raises(RuntimeError) { load_initializer(app_root) }

      assert_match(/expected a directory/, error.message)
      assert_equal "keep", File.read(path)
    end
  end

  def test_valid_nested_asset_directory_is_removed
    Dir.mktmpdir("propshaft-app-") do |app_root|
      nested = File.join(app_root, "public", "assets", "assets")
      FileUtils.mkdir_p(nested)
      File.write(File.join(nested, "stale.css"), "stale")

      load_initializer(app_root)

      refute File.exist?(nested)
    end
  end
end
