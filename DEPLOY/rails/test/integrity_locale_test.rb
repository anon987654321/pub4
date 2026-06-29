# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "rbconfig"

class IntegrityLocaleTest < Minitest::Test
  ROOT = File.expand_path("../../..", __dir__)
  GATE = File.join(ROOT, "DEPLOY", "integrity_gate.rb")

  def test_integrity_chain_is_independent_of_operator_locale
    env = { "LANG" => nil, "LC_ALL" => "C", "LC_CTYPE" => nil }
    output, status = Open3.capture2e(env, RbConfig.ruby, GATE, chdir: ROOT)

    assert status.success?, output
    assert_includes output, "integrity: clean"
    refute_includes output, "invalid byte sequence"
  end
end
