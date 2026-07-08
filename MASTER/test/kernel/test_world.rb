# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../kernel/master"
require "tmpdir"

# The World is the only door to reality, so its handlers carry the whole blast
# radius of the agent. These pin the invariants every handler must hold:
# the sandbox never opens, writes replace atomically, and a failed exec is
# reported as data (err Observation), never raised.
class WorldTest < Minitest::Test
  E = Master::Kernel::Effect

  def with_world
    Dir.mktmpdir { |root| yield Master::Kernel::World.new(root:), root }
  end

  def test_read_returns_file_contents
    with_world do |world, root|
      File.write(File.join(root, "a.txt"), "hello\n")
      obs = world.perform(E.read("a.txt"))
      assert obs.ok?
      assert_equal "hello\n", obs.value!
    end
  end

  def test_write_creates_nested_dirs_and_content
    with_world do |world, root|
      obs = world.perform(E.write("deep/nested/a.rb", "A = 1\n"))
      assert obs.ok?, obs.message
      assert_equal "A = 1\n", File.read(File.join(root, "deep/nested/a.rb"))
    end
  end

  def test_write_replaces_existing_atomically_and_leaves_no_tmp
    with_world do |world, root|
      File.write(File.join(root, "a.rb"), "old\n")
      world.perform(E.write("a.rb", "new\n"))
      assert_equal "new\n", File.read(File.join(root, "a.rb"))
      # No .tmp or .bak litter beside the target — the write is one atomic rename.
      assert_equal ["a.rb"], Dir.children(root).sort
    end
  end

  def test_path_escaping_the_sandbox_is_refused_not_raised
    with_world do |world|
      obs = world.perform(E.read("../../etc/passwd"))
      assert obs.err?
      assert_match(/escapes workspace/, obs.message)
    end
  end

  def test_write_escaping_the_sandbox_is_refused
    with_world do |world, root|
      obs = world.perform(E.write("../evil.txt", "x"))
      assert obs.err?
      refute File.exist?(File.expand_path("../evil.txt", root))
    end
  end

  def test_exec_success_returns_stdout
    with_world do |world|
      obs = world.perform(E.exec([RbConfig.ruby, "-e", "print 'ok'"]))
      assert obs.ok?
      assert_equal "ok", obs.value!
    end
  end

  def test_exec_failure_is_err_observation_not_raise
    with_world do |world|
      obs = world.perform(E.exec([RbConfig.ruby, "-e", "exit 3"]))
      assert obs.err?
    end
  end

  def test_exec_rejects_non_array_argv
    with_world do |world|
      obs = world.perform(E.new(verb: :exec, args: { argv: "rake test" }))
      assert obs.err?
      assert_match(/argv must be an array/, obs.message)
    end
  end
end
