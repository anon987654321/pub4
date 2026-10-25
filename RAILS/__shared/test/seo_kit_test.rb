# frozen_string_literal: true

require "test_helper"

class SharedSeoKitTest < ActionView::TestCase
  include Shared::SeoKit
  include SchemaHelper

  def test_json_ld_script_escapes_html_sensitive_characters
    rendered = json_ld_script({ "name" => %q(</script><script>alert("x")</script>&) })

    assert_safe_json_ld(rendered)
  end

  def test_json_ld_for_uses_the_shared_safe_serializer
    rendered = json_ld_for(Object.new, type: :thing)

    assert_safe_json_ld(rendered)
  end

  private

  def build_schema(_resource, _explicit_type)
    { "name" => %q(</script><script>alert("x")</script>&) }
  end

  def assert_safe_json_ld(rendered)
    assert_includes rendered, 'type="application/ld+json"'
    assert_match(%r{\\u003c/script\\u003e}i, rendered)
    assert_includes rendered, "\\u0026"
    refute_includes rendered, "</script><script>"
  end
end
