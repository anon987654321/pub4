# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require_relative "../lib/fix/primitive_first"

class TestFixPrimitiveFirst < Minitest::Test
  PF = Master::Fix::PrimitiveFirst

  def setup
    @root = Dir.mktmpdir
    shared = File.join(@root, PF::SHARED_DIR)
    FileUtils.mkdir_p(shared)
    File.write(File.join(shared, "_components.scss"), ".tag {\n  color: red;\n}\n\n.btn,\n.btn-wide {\n  padding: 1px;\n}\n.stack { display: flex; }\n")
    2.times do |n|
      dir = File.join(@root, "RAILS", "brgen", "app", "views", "p#{n}")
      FileUtils.mkdir_p(dir)
      File.write(File.join(dir, "show.html.erb"), "<a class=\"btn\">x</a>")
    end
  end

  def teardown = FileUtils.remove_entry(@root)

  def test_hint_names_the_owning_rule_when_two_pages_share_the_selector
    text = PF.hint({ anchor: ".btn", file: "#{@root}/RAILS/brgen/app/assets/stylesheets/application.scss" }, root: @root)

    assert_includes text, "Edit the primitive at RAILS/__shared/app/assets/stylesheets/_components.scss:5"
    assert_includes text, "do not add page-scoped overrides"
  end

  def test_hint_is_silent_for_a_selector_on_one_page
    File.delete(File.join(@root, "RAILS", "brgen", "app", "views", "p1", "show.html.erb"))

    assert_nil PF.hint({ anchor: ".btn" }, root: @root)
  end

  def test_page_scoped_override_of_a_shared_class_is_refused
    why = PF.check("#{@root}/RAILS/brgen/app/assets/stylesheets/application.scss", "", "body.page-home .btn { margin: 0; }", root: @root)

    assert_match(/page-scoped override of shared primitive \.btn/, why)
  end

  def test_component_nesting_and_unshared_classes_pass
    path = "#{@root}/RAILS/brgen/app/assets/stylesheets/application.scss"

    assert_nil PF.check(path, "", ".card .btn { margin: 0; }\n.page-title { margin: 0; }", root: @root)
  end

  def test_shared_stylesheet_edits_and_non_css_are_not_checked
    assert_nil PF.check("#{@root}/#{PF::SHARED_DIR}/_components.scss", "", "body .btn { margin: 0; }", root: @root)
    assert_nil PF.check("#{@root}/a.rb", "", "body .btn { margin: 0; }", root: @root)
  end

  def test_existing_override_is_not_blamed_on_the_new_patch
    old = "body.page-home .btn { margin: 0; }"

    assert_nil PF.check("#{@root}/RAILS/brgen/x.scss", old, "#{old}\n.other { top: 0; }", root: @root)
  end

  def test_layout_advice_is_logged_not_refused
    seen = []
    Master::Trace::Dmesg.stub(:status, ->(unit, msg, **) { seen << "#{unit}: #{msg}" }) do
      assert_nil PF.check("#{@root}/RAILS/brgen/x.scss", "", ".rows { display: flex; flex-direction: column; gap: 1rem; }", root: @root)
    end

    assert_match(/prim0: \.rows rebuilds \.stack/, seen.join)
  end

  def test_shared_layout_primitives_partial_defines_every_name
    css = File.read(File.expand_path("../../RAILS/__shared/app/assets/stylesheets/_layout_primitives.scss", __dir__))

    %w[.switcher .with-sidebar .auto-grid].each { |name| assert_includes css, name }
  end
end
