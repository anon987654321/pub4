# frozen_string_literal: true

require "minitest/autorun"
require "master"

class CoreMemoryViewTest < Minitest::Test
  def test_unveil_accepts_exact_paths_and_subtrees
    memory = Master::Core::Memory.new
    memory.unveil("mission/current.json" => :read, "workspace" => :write)

    assert memory.memory_allowed?("mission/current.json")
    assert memory.memory_allowed?("workspace/file.rb", :read)
    assert memory.memory_allowed?("workspace/file.rb", :write)
    refute memory.memory_allowed?("owner/private.json")
  end

  def test_unveil_is_monotonic_after_lock
    memory = Master::Core::Memory.new
    memory.unveil("mission/current.json" => :read)
    memory.lock!

    assert memory.view.locked?
    assert_raises(SecurityError) { memory.unveil("secrets.yml") }
  end

  def test_forbidden_memory_access_has_a_specific_error
    memory = Master::Core::Memory.new
    error = assert_raises(SecurityError) { memory.view.require!("owner/private.json") }

    assert_match(/memory view refused/, error.message)
  end
end
