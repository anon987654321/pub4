# frozen_string_literal: true

require_relative "test_helper"
require "json"
require "open3"

# tools/law_check_edit.rb is a PreToolUse hook: exit 2 blocks the edit, anything else lets it through.
class TestLawCheckEdit < Minitest::Test
  HOOK = File.expand_path("../tools/law_check_edit.rb", __dir__)
  REPO = File.expand_path("../..", __dir__)
  SECRET = "API_KEY = \"sk-ant-abcdefghijklmnopqrstuvwxyz0123456789\"\n"

  def call(payload)
    stdin = payload.is_a?(String) ? payload : JSON.generate(payload)
    out, status = Open3.capture2e(RbConfig.ruby, HOOK, stdin_data: stdin)
    [status.exitstatus, out]
  end

  def write(path, content) = { "tool_name" => "Write", "tool_input" => { "file_path" => path, "content" => content } }

  def test_a_clean_write_passes
    code, = call(write(File.join(REPO, "MASTER", "lib", "zz_probe.rb"), "# frozen_string_literal: true\n\nX = 1\n"))

    assert_equal 0, code
  end

  def test_an_introduced_secret_is_refused_with_the_reason
    code, out = call(write(File.join(REPO, "MASTER", "lib", "zz_probe.rb"), SECRET))

    assert_equal 2, code
    assert_match(/SECRET_PROXIMITY/, out)
  end

  def test_laws_and_soul_are_not_refused_by_path_alone
    %w[laws soul].each do |name|
      path = File.join(REPO, "MASTER", "data", "#{name}.yml")
      code, out = call(write(path, File.read(path, encoding: "UTF-8")))

      assert_equal 0, code, "#{name}: #{out}"
      refute_match(/immutable/, out)
    end
  end

  def test_a_file_outside_the_checkout_and_unreadable_input_pass
    assert_equal 0, call(write("/tmp/outside-checkout/x.rb", SECRET)).first
    assert_equal 0, call("not json").first
  end
end
