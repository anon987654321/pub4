# frozen_string_literal: true

require_relative "test_helper"
require "json"
require "tmpdir"
require_relative "../lib/fix/design_edit"

class TestMarkupEdit < Minitest::Test
  EDIT = Master::Fix::DesignEdit
  VIEW = %(<main>\n  <section class="card">\n    <h1 class="title"><%= t(".title") %></h1>\n  </section>\n</main>\n)
  CLASSES = %w[card title stack wide hidden].freeze

  def with_view
    Dir.mktmpdir do |dir|
      path = File.join(dir, "show.html.erb")
      File.write(path, VIEW)
      yield path
    end
  end

  def parse(path, find:, replace:)
    reply = JSON.generate("file" => path, "find" => find, "replace" => replace, "why" => "x")
    EDIT.parse(reply, allowed: [path], rules: EDIT::Rules.new(guard: nil, scale: nil, classes: CLASSES))
  end

  def refused(edit) = assert_raises(EDIT::Refused) { edit.check! }.message

  def test_a_view_is_edited_by_the_markup_rules
    with_view do |path|
      assert_predicate parse(path, find: 'class="card"', replace: 'class="card stack"'), :markup?
    end
  end

  def test_a_defined_class_may_be_added_to_a_static_class_attribute
    with_view do |path|
      edit = parse(path, find: 'class="card"', replace: 'class="card stack"')

      assert edit.check!
      edit.apply!
      assert_includes File.read(path), 'class="card stack"'
    end
  end

  def test_the_selector_tokens_are_the_classes_the_element_already_has
    with_view do |path|
      edit = parse(path, find: 'class="card wide"', replace: 'class="card wide stack"')

      assert_equal %w[.card .wide], edit.selector_tokens
    end
  end

  def test_removing_a_class_is_refused
    with_view do |path|
      assert_match(/remove/, refused(parse(path, find: 'class="card"', replace: 'class="stack"')))
    end
  end

  def test_a_class_no_offered_stylesheet_defines_is_refused
    with_view do |path|
      assert_match(/not defined/, refused(parse(path, find: 'class="card"', replace: 'class="card invented"')))
    end
  end

  def test_a_class_that_hides_content_is_refused
    with_view do |path|
      assert_match(/hides/, refused(parse(path, find: 'class="card"', replace: 'class="card hidden"')))
    end
  end

  def test_text_and_erb_stay_untouched
    with_view do |path|
      text = parse(path, find: %(<h1 class="title"><%= t(".title") %></h1>), replace: %(<h1 class="title stack">Title</h1>))
      assert_match(/only add class names/, refused(text))
    end
  end

  def test_the_text_to_replace_must_occur_once
    with_view do |path|
      File.write(path, VIEW * 2)

      assert_match(/2 times/, refused(parse(path, find: 'class="card"', replace: 'class="card stack"')))
    end
  end

  def test_a_file_that_was_not_offered_is_refused
    with_view do |path|
      edit = EDIT.parse(JSON.generate("file" => "/etc/hosts.erb", "find" => "a", "replace" => "b"), allowed: [path])

      assert_match(/not one of the offered/, refused(edit))
    end
  end
end
