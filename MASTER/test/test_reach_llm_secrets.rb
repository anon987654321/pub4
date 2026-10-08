# frozen_string_literal: true

require_relative "test_helper"

class TestReachLlmSecrets < Minitest::Test
  HARDCODED_SECRET_RE = /
    sk-[A-Za-z0-9_-]{20,}|
    AIza[A-Za-z0-9_-]{20,}|
    xox[baprs]-[A-Za-z0-9-]{20,}|
    ghp_[A-Za-z0-9_]{20,}|
    github_pat_[A-Za-z0-9_]{20,}
  /x

  def test_reach_llm_has_no_hardcoded_api_keys
    source = File.read(File.join(Master::ROOT, "lib", "io", "llm.rb"), encoding: "UTF-8")

    refute_match HARDCODED_SECRET_RE, source
  end
end
