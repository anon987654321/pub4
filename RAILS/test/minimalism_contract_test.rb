# frozen_string_literal: true

require "minitest/autorun"

class MinimalismContractTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  def test_minimalism_law_is_the_house_source
    source = File.read(File.join(ROOT, "MASTER/data/minimalism.yml"))
    assert_includes source, "bordered_nesting_max: 2"
    assert_includes source, "max_zones: 3"
    assert_includes source, "console_errors: 0"
    assert_includes source, "dead_links: 0"
  end

  def test_console_guard_is_loaded_once_and_emits_house_event
    source = File.read(File.join(ROOT, "RAILS/__shared/frontend/console_guard.js"))
    assert_includes source, "pub4:console-error"
    assert_includes source, "unhandledrejection"
  end

  def test_audits_are_report_first_not_decoration_first
    source = File.read(File.join(ROOT, "MASTER/tools/minimal_audit.rb"))
    assert_includes source, "MINIMAL_AUDIT_STRICT"
    assert_includes source, "box_shadow"
    assert_includes source, "href_hash"
  end
end
