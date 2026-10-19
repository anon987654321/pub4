# frozen_string_literal: true

require "minitest/autorun"

class PostproBootstrapContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  ENTRYPOINT = File.join(ROOT, "postpro", "postpro.rb")
  BOOTSTRAP = File.join(ROOT, "postpro", "bootstrap.rb")

  def test_bootstrap_policy_is_separate_and_installation_remains_explicit
    entry = File.read(ENTRYPOINT)
    bootstrap = File.read(BOOTSTRAP)

    assert_includes entry, 'require_relative "bootstrap"'
    assert_includes entry, "BOOTSTRAP = PostproBootstrap.run"
    assert_includes bootstrap, 'def self.install_allowed? = ENV["POSTPRO_INSTALL_DEPS"] == "1"'
    assert_includes bootstrap, "def self.ensure_gems"
    refute_match(/POSTPRO_INSTALL_DEPS.*=\s*["']1["']/, entry)
  end

  def test_bootstrap_module_keeps_its_own_required_dependencies
    source = File.read(BOOTSTRAP)

    %w[fileutils json open3 rbconfig time].each do |library|
      assert_includes source, %(require "#{library}")
    end
    assert_includes source, "BOOT_TIME = Time.now.freeze"
    assert_includes source, "module PostproBootstrap"
  end
end
