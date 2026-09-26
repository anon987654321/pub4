# frozen_string_literal: true

require_relative "test_helper"
require "open3"
require "tmpdir"
require "fileutils"
require_relative "../lib/operator/ruby_runner"

# bin/ruby picks ruby34, ruby3.4 or rbenv's ruby and execs the rest of the line.
# Whichever it picks, the line must run under it with its arguments intact.
class TestBinRuby < Minitest::Test
  BIN = File.expand_path("../bin/ruby", __dir__)

  def test_it_execs_a_ruby_with_the_arguments_intact
    out, err, status = unbundled { Open3.capture3(BIN, "-e", "print RUBY_VERSION, ' ', ARGV.join(',')", "--", "a b", "c") }

    assert status.success?, err
    assert_match(/\A\d+\.\d+\.\d+ a b,c\z/, out)
  end

  def test_command_path_finds_executables_on_path_without_a_shell_builtin
    old_path = ENV["PATH"]

    Dir.mktmpdir do |root|
      fake_bin = File.join(root, "bin")
      FileUtils.mkdir_p(fake_bin)
      command = File.join(fake_bin, "ruby34")
      File.write(command, "#!/bin/sh\n")
      File.chmod(0o755, command)
      ENV["PATH"] = "#{fake_bin}#{File::PATH_SEPARATOR}#{old_path}"

      assert_equal command, Operator::RubyRunner.command_path("ruby34")
    ensure
      ENV["PATH"] = old_path
    end
  end

  def test_rbenv_path_uses_the_repo_pinned_version
    old_path = ENV["PATH"]
    old_fake_path = ENV["FAKE_RBENV_PATH"]

    Dir.mktmpdir do |root|
      fake_bin = File.join(root, "bin")
      FileUtils.mkdir_p(fake_bin)
      ruby_path = File.join(root, "ruby-3.4.9")
      File.write(ruby_path, "#!/usr/bin/env ruby\\n")
      File.chmod(0o755, ruby_path)
      rbenv = File.join(fake_bin, "rbenv")
      File.write(rbenv, <<~RUBY)
        #!/usr/bin/env ruby
        abort "wrong version" unless ENV["RBENV_VERSION"] == "3.4.9"
        puts ENV.fetch("FAKE_RBENV_PATH")
      RUBY
      File.chmod(0o755, rbenv)
      File.write(File.join(root, ".ruby-version"), "3.4.9\\n")

      ENV["PATH"] = "#{fake_bin}#{File::PATH_SEPARATOR}#{old_path}"
      ENV["FAKE_RBENV_PATH"] = ruby_path

      assert_equal ruby_path, Operator::RubyRunner.rbenv_path("ruby", root:)
    ensure
      ENV["PATH"] = old_path
      ENV["FAKE_RBENV_PATH"] = old_fake_path
    end
  end

  def test_ruby_runner_prefers_the_pinned_rbenv_over_generic_ruby34
    old_path = ENV["PATH"]
    old_fake_path = ENV["FAKE_RBENV_PATH"]

    Dir.mktmpdir do |root|
      fake_bin = File.join(root, "bin")
      FileUtils.mkdir_p(fake_bin)
      ruby_path = File.join(root, "ruby-3.4.9")
      File.write(ruby_path, "#!/usr/bin/env ruby\\n")
      File.chmod(0o755, ruby_path)
      rbenv = File.join(fake_bin, "rbenv")
      File.write(rbenv, <<~RUBY)
        #!/usr/bin/env ruby
        abort "wrong version" unless ENV["RBENV_VERSION"] == "3.4.9"
        puts ENV.fetch("FAKE_RBENV_PATH")
      RUBY
      File.chmod(0o755, rbenv)
      generic = File.join(fake_bin, "ruby34")
      File.write(generic, "#!/bin/sh\\nexit 99\\n")
      File.chmod(0o755, generic)
      File.write(File.join(root, ".ruby-version"), "3.4.9\\n")

      ENV["PATH"] = "#{fake_bin}#{File::PATH_SEPARATOR}#{old_path}"
      ENV["FAKE_RBENV_PATH"] = ruby_path

      assert_equal ruby_path, Operator::RubyRunner.ruby_cmd
    ensure
      ENV["PATH"] = old_path
      ENV["FAKE_RBENV_PATH"] = old_fake_path
    end
  end

  def test_a_failing_script_keeps_its_exit_status
    _, _, status = unbundled { Open3.capture3(BIN, "-e", "exit 7") }

    assert_equal 7, status.exitstatus
  end

  private

  # The suite runs under bundle exec; the Ruby bin/ruby picks may not share that
  # bundle, so the child gets a clean environment.
  def unbundled(&) = defined?(Bundler) ? Bundler.with_unbundled_env(&) : yield
end
