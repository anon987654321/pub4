# frozen_string_literal: true

require_relative "test_helper"
require "review/scan/rule_dsl"

class TestWebRules < Minitest::Test
  def rule(id)
    candidates = Master::Review::Scan::Rule.registry.filter_map do |klass|
      instance = klass.new
      instance if instance.id == id
    rescue ArgumentError
      nil
    end
    candidates.first || flunk("missing rule #{id}")
  end

  def test_prefer_tag_helpers_flags_simple_wrapper
    findings = rule("PREFER_TAG_HELPERS").check(%(<p><%= t("hello_world") %></p>\n), path: "/repo/app/views/home/index.html.erb")
    refute_empty findings
  end

  def test_prefer_tag_helpers_flags_wrapper_with_attributes
    findings = rule("PREFER_TAG_HELPERS").check(%(<div class="card"><%= item.title %></div>\n), path: "/repo/app/views/items/show.html.erb")
    refute_empty findings
  end

  def test_prefer_tag_helpers_ignores_mixed_text_and_erb
    findings = rule("PREFER_TAG_HELPERS").check(%(<p>Hello <%= @user.name %>, welcome</p>\n), path: "/repo/app/views/home/index.html.erb")
    assert_empty findings
  end

  def test_prefer_tag_helpers_ignores_tag_helper_already_used
    findings = rule("PREFER_TAG_HELPERS").check(%(<%= tag.p t("hello_world") %>\n), path: "/repo/app/views/home/index.html.erb")
    assert_empty findings
  end

  def test_prefer_tag_helpers_ignores_multiple_children
    findings = rule("PREFER_TAG_HELPERS").check(%(<div><span>x</span><span>y</span></div>\n), path: "/repo/app/views/home/index.html.erb")
    assert_empty findings
  end

  def test_prefer_tag_helpers_ignores_outside_app_views
    findings = rule("PREFER_TAG_HELPERS").check(%(<p><%= t("hello_world") %></p>\n), path: "/repo/spec/fixtures/sample.html.erb")
    assert_empty findings
  end
end
