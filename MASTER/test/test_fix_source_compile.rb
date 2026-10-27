# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/fix/source_compile"

# A repaired view, stylesheet or script must still compile before /fix keeps it.
class TestFixSourceCompile < Minitest::Test
  Compile = Master::Fix::SourceCompile
  RAILS = File.join(Master::REPO_ROOT, "RAILS")

  def with_file(relative, body)
    path = File.join(RAILS, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, body)
    yield path
  ensure
    FileUtils.rm_f(path)
  end

  def test_a_view_with_a_block_helper_and_a_layout_yield_compiles
    view = "<%= form_with url: \"/\" do |f| %><%= yield %><% end %>\n"
    with_file("brgen/app/views/fix_probe/_ok.html.erb", view) do |path|
      assert_nil Compile.failure(path)
    end
  ensure
    FileUtils.rm_rf(File.join(RAILS, "brgen/app/views/fix_probe"))
  end

  def test_a_view_left_open_does_not
    with_file("brgen/app/views/fix_probe/_open.html.erb", "<% if true %>\n<p>x</p>\n") do |path|
      assert_match(/does not compile/, Compile.failure(path))
    end
  ensure
    FileUtils.rm_rf(File.join(RAILS, "brgen/app/views/fix_probe"))
  end

  def test_a_shared_stylesheet_is_judged_by_every_app_entry
    found = "#{RAILS}/__shared/app/assets/stylesheets/_x.scss".match(Compile::RAILS_PATH)

    assert_equal %w[amber brgen bsdports], Compile.entries(found, ".scss").map { |entry| entry.split("/")[-5] }.sort
  end

  def test_a_script_with_a_syntax_error_is_refused_and_files_outside_rails_are_not_read
    with_file("brgen/app/javascript/fix_probe_broken.js", "export function x( {\n") do |path|
      assert_match(/SyntaxError/, Compile.failure(path))
    end
    assert_nil Compile.failure(File.join(Master::ROOT, "lib", "master.rb"))
  end
end
