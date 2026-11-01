# frozen_string_literal: true

require "test_helper"

class TestRubySelectorEnvironment < Minitest::Test
  def test_malloc_stack_logging_is_removed_before_any_ruby_probe
    source = File.read(File.join(Master::ROOT, "bin", "ruby"), encoding: "UTF-8")
    cleanup = source.index("MallocStackLogging*")
    first_probe = source.index('version=$("$ruby" -e')

    refute_nil cleanup, "the shell launcher must clear inherited allocator diagnostics"
    refute_nil first_probe, "the launcher must retain its candidate version probe"
    assert_operator cleanup, :<, first_probe,
                    "cleanup must run before the first Ruby process starts"
    assert_match(/unset "\$name"/, source)
  end
end
