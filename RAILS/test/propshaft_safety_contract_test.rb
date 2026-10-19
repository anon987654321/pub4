# frozen_string_literal: true

require "minitest/autorun"

class PropshaftSafetyContractTest < Minitest::Test
  REPO_ROOT = File.expand_path("../..", __dir__)
  INITIALIZER = File.join(REPO_ROOT, "RAILS", "master", "config", "initializers", "propshaft_safety.rb")

  def test_recursive_asset_cleanup_requires_a_real_directory
    source = File.read(INITIALIZER)

    assert_includes source, "File.symlink?(nested)"
    assert_includes source, "nested.directory?"
    assert_includes source, 'FileUtils.rm_rf(nested)'
  end
end
