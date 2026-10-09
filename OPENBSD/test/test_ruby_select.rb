# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"

# OPENBSD/lib/ruby_select.sh is the one place the deploy path picks a Ruby, so
# these run it under sh and zsh against a throwaway PATH holding fake
# interpreters: the box has only ruby34, a developer machine may have ruby40,
# and the same scripts must run on both without naming either.
class TestRubySelect < Minitest::Test
  LIB = File.expand_path("../lib/ruby_select.sh", __dir__)

  def with_path(*names)
    Dir.mktmpdir do |dir|
      names.each do |name|
        path = File.join(dir, name)
        version = name[/\d+/] == "40" ? "40" : "34"
        File.write(path, "#!/bin/sh\nprintf #{version}\n")
        FileUtils.chmod(0o755, path)
      end
      yield dir
    end
  end

  def resolve(dir, shell: "/bin/sh", env: {})
    script = '. "$1" && printf "%s|%s|%s|%s|%s" "$RUBY" "$RUBY_SUFFIX" "$BUNDLE" "$GEM" "$RUBY_CACHE_KEY"'
    out, err, status = Open3.capture3({ "PATH" => dir, "RUBY" => nil }.merge(env), shell, "-c", script, shell, LIB, unsetenv_others: true)
    [out, err, status]
  end

  def shells
    ["/bin/sh", *Dir["/bin/zsh", "/usr/bin/zsh", "/opt/homebrew/bin/zsh"].first(1)]
  end

  def test_prefers_ruby40_when_both_exist
    with_path("ruby34", "ruby40", "bundle34", "bundle40", "gem40") do |dir|
      shells.each do |shell|
        out, err, status = resolve(dir, shell: shell)
        assert status.success?, err
        assert_equal [File.join(dir, "ruby40"), "40", File.join(dir, "bundle40"), File.join(dir, "gem40"), "ruby40"], out.split("|")
      end
    end
  end

  def test_uses_ruby34_when_it_is_the_only_one
    with_path("ruby34", "bundle34", "gem34") do |dir|
      shells.each do |shell|
        out, err, status = resolve(dir, shell: shell)
        assert status.success?, err
        assert_equal [File.join(dir, "ruby34"), "34", File.join(dir, "bundle34"), File.join(dir, "gem34"), "ruby34"], out.split("|")
      end
    end
  end

  def test_falls_back_to_plain_tools_when_suffixed_ones_are_missing
    with_path("ruby34", "bundle", "gem") do |dir|
      out, = resolve(dir)
      assert_equal File.join(dir, "bundle"), out.split("|")[2]
      assert_equal File.join(dir, "gem"), out.split("|")[3]
    end
  end

  def test_dotted_suffix_outranks_the_undotted_name
    with_path("ruby3.4", "ruby34", "bundle3.4") do |dir|
      out, = resolve(dir)
      assert_equal [File.join(dir, "ruby3.4"), "3.4", File.join(dir, "bundle3.4")], out.split("|").first(3)
    end
  end

  def test_env_override_wins
    with_path("ruby34", "ruby40", "bundle34") do |dir|
      out, = resolve(dir, env: { "RUBY" => File.join(dir, "ruby34") })
      assert_equal [File.join(dir, "ruby34"), "34", File.join(dir, "bundle34")], out.split("|").first(3)
    end
  end

  def test_errors_when_no_ruby_exists
    skip "a package ruby exists in /usr/local/bin" if Dir["/usr/local/bin/ruby*"].any?
    with_path do |dir|
      _out, err, status = resolve(dir)
      refute status.success?
      assert_match(/no Ruby found/, err)
    end
  end
end
