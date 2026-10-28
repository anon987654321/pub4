# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/fix/resource_budget"

class TestResourceBudgetDisk < Minitest::Test
  Status = Struct.new(:ok) do
    def success? = ok
  end

  def setup
    @budget = Master::Fix::ResourceBudget.new(root: Dir.pwd, config: {})
  end

  def test_parses_available_kib_from_df_output
    path = "/tmp/work tree"
    output = <<~DF
      Filesystem 1024-blocks Used Available Capacity Mounted on
      /dev/mock 10000000 1000000 2097152 10% /
    DF

    with_df(path, output) do
      assert_equal 2.0, @budget.disk_free_gb_for(path)
    end
  end

  def test_uses_the_available_header_instead_of_a_fixed_column
    path = "/tmp/work tree"
    output = <<~DF
      Filesystem Used Capacity Available Mounted on
      /dev/mock 1000000 10% 2097152 /
    DF

    with_df(path, output) do
      assert_equal 2.0, @budget.disk_free_gb_for(path)
    end
  end

  def test_parses_openbsd_avail_header
    path = "/tmp/work tree"
    output = <<~DF
      Filesystem 1K-blocks Used Avail Capacity Mounted on
      /dev/mock 10000000 1000000 2097152 10% /
    DF

    with_df(path, output) do
      assert_equal 2.0, @budget.disk_free_gb_for(path)
    end
  end

  def test_malformed_or_header_only_df_output_is_unavailable
    path = "/tmp/work tree"
    [
      "df: measurement unavailable\n",
      "Filesystem 1024-blocks Used Available Capacity Mounted on\n",
      "Filesystem 1024-blocks Used Available Capacity Mounted on\n/dev/mock 1000 900 unknown 90% /\n",
    ].each do |output|
      with_df(path, output) do
        assert_nil @budget.disk_free_gb_for(path), "expected malformed df output to remain unavailable"
      end
    end
  end

  def test_failed_df_command_is_unavailable
    path = "/tmp/work tree"
    with_df(path, "", success: false) do
      assert_nil @budget.disk_free_gb_for(path)
    end
  end

  private

  def with_df(path, output, success: true)
    status = Status.new(success)
    Master::Io::Exec.stub(:capture2e, lambda do |*args|
      assert_equal ["df", "-kP", path], args
      [output, status]
    end) do
      yield
    end
  end
end
