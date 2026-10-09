# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"
require "rbconfig"

# __shared/test/coverage.rb ran on vm23 as "unknown Rails app brgen": it looked
# for <root>/brgen, and the deploy copy-tree keeps the app at <root>/app beside
# __shared. This runs the real file against a temp tree in each layout, with a
# stand-in for simplecov, so no gem and no Rails boot is needed.
class CoverageLayoutTest < Minitest::Test
  SOURCE = File.expand_path("../__shared/test/coverage.rb", __dir__)
  FAKE_SIMPLECOV = <<~RUBY
    module SimpleCov
      def self.root(path) = puts("root=\#{path}")
      def self.coverage_path(path) = puts("path=\#{path}")
      def self.command_name(name) = puts("command=\#{name}")
      def self.start(*) = nil
    end
  RUBY

  def run_in(layout_dir, app:, cwd:)
    Dir.mktmpdir do |tmp|
      FileUtils.mkdir_p(File.join(tmp, "stub"))
      File.write(File.join(tmp, "stub", "simplecov.rb"), FAKE_SIMPLECOV)
      FileUtils.mkdir_p(File.join(tmp, "root", "__shared", "test"))
      FileUtils.cp(SOURCE, File.join(tmp, "root", "__shared", "test", "coverage.rb"))
      FileUtils.mkdir_p(File.join(tmp, "root", layout_dir, "config"))
      FileUtils.touch(File.join(tmp, "root", layout_dir, "config", "application.rb"))
      out, err, status = Open3.capture3(
        { "PUB4_CI_APP" => app, "PUB4_COVERAGE_PATH" => nil },
        RbConfig.ruby, "-I", File.join(tmp, "stub"), File.join(tmp, "root", "__shared", "test", "coverage.rb"),
        chdir: File.join(tmp, "root", cwd)
      )
      [status, out.gsub(File.join(tmp, "root"), "ROOT"), err]
    end
  end

  def test_monorepo_layout_finds_RAILS_app_dir
    status, out, err = run_in("brgen", app: "brgen", cwd: "brgen")
    assert status.success?, err
    assert_includes out, "command=brgen:rails"
  end

  def test_copy_tree_layout_finds_the_app_dir_named_app
    status, out, err = run_in("app", app: "brgen", cwd: "app")
    assert status.success?, err
    assert_match %r{^path=.*/coverage/brgen$}, out
  end

  def test_an_app_with_no_directory_is_still_refused
    status, _out, err = run_in("elsewhere", app: "brgen", cwd: "elsewhere")
    refute status.success?
    assert_includes err, "unknown Rails app"
  end
end
