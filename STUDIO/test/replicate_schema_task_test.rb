# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"

class ReplicateSchemaTaskTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def run_without_credentials(task)
    Dir.mktmpdir("studio-no-replicate-token-") do |home|
      env = {
        "HOME" => home,
        "REPLICATE_API_TOKEN" => nil,
        "REPLICATE_API_KEY" => nil,
        "BUNDLE_GEMFILE" => nil,
        "RUBYOPT" => nil,
      }
      Open3.capture2e(env, RbConfig.ruby, "-S", "rake", task, chdir: ROOT)
    end
  end

  def test_schema_audit_is_inconclusive_without_credentials
    output, status = run_without_credentials("replicate:schema_audit")

    assert_equal 3, status.exitstatus, output
    assert_includes output, "schema audit inconclusive"
    refute_includes output, "0 of 0 models need attention"
  end

  def test_schema_snapshot_is_inconclusive_without_credentials
    output, status = run_without_credentials("replicate:schema_snapshot")

    assert_equal 3, status.exitstatus, output
    assert_includes output, "schema snapshot inconclusive"
  end
end
