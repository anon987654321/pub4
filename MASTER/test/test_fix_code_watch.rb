# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

# /fix kept the code it booted with for hours, asking the model about findings
# that fixes already on origin/main had removed.
class TestFixCodeWatch < Minitest::Test
  Watch = Master::Fix::CodeWatch

  def setup = reset
  def teardown = reset

  def reset
    Watch.instance_variable_set(:@checked_at, nil)
    Watch.instance_variable_set(:@requested, false)
  end

  def git(dir, *args) = system("git", "-C", dir, *args, out: File::NULL, err: File::NULL) || flunk("git #{args.join(" ")}")

  def commit(dir, path, body)
    FileUtils.mkdir_p(File.dirname(File.join(dir, path)))
    File.write(File.join(dir, path), body)
    git(dir, "add", path)
    git(dir, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", path)
  end

  def with_clone
    Dir.mktmpdir do |tmp|
      origin = File.join(tmp, "origin")
      git(tmp, "init", "-q", "-b", "main", origin)
      commit(origin, "MASTER/lib/a.rb", "a\n")
      git(tmp, "clone", "-q", origin, File.join(tmp, "work"))
      yield origin, File.join(tmp, "work", "MASTER")
    end
  end

  def test_new_master_code_on_origin_makes_the_run_stale
    with_clone do |origin, root|
      refute Watch.stale?(root)

      commit(origin, "MASTER/lib/a.rb", "b\n")
      Watch.instance_variable_set(:@checked_at, nil)
      assert Watch.stale?(root)
      assert Watch.requested?
    end
  end

  def test_a_change_outside_master_code_does_not
    with_clone do |origin, root|
      commit(origin, "RAILS/app.rb", "x\n")
      refute Watch.stale?(root)
    end
  end
end
