# frozen_string_literal: true

require "test_helper"

# Every port view forked a pkg_info process; one answer now serves a package's
# views for a few minutes.
class Ports::LocalPackageTest < ActiveSupport::TestCase
  Status = Struct.new(:ok) do
    def success? = ok
  end

  def counting_pkg_info(calls, answer:, ok: true)
    lambda do |*_command|
      calls << 1
      [ answer, Status.new(ok) ]
    end
  end

  test "one pkg_info answer serves repeated views of a package" do
    calls = []
    cache = ActiveSupport::Cache::MemoryStore.new

    Open3.stub(:capture2e, counting_pkg_info(calls, answer: "git-2.45.0\n")) do
      2.times { assert_equal "git-2.45.0", Ports::LocalPackage.info("git", cache:) }
    end
    assert_equal 1, calls.size, "pkg_info forked once per view"
  end

  test "a package that is not installed reads as empty, and a host without pkg_info as unknown" do
    cache = ActiveSupport::Cache::MemoryStore.new

    Open3.stub(:capture2e, counting_pkg_info([], answer: "no such package", ok: false)) do
      assert_equal "", Ports::LocalPackage.info("absent", cache:)
    end
    Open3.stub(:capture2e, ->(*) { raise Errno::ENOENT }) do
      assert_nil Ports::LocalPackage.info("unknown", cache:)
    end
  end
end
