# frozen_string_literal: true

require_relative "test_helper"

class TestWatcher < Minitest::Test
  def test_openbsd_vmm_memory_pressure_without_swap
    watcher = Master::Fix::Watcher.allocate
    vmstat = <<~VMSTAT
      procs    memory       page                    disks    traps          cpu
       r b w    avm    fre  flt  re  pi  po  fr  sr sd0  int   sys   cs us sy id
       0 0 0   120M   256M    0   0   0   0   0   0   0  124   456   78  0  1 99
    VMSTAT

    free = watcher.send(:vmstat_free_bytes, vmstat)
    total = watcher.send(:physmem_bytes, "1073741824\n")

    assert_equal 268_435_456, free
    assert_equal 25.0, watcher.send(:memory_free_percent, free, total)
  end

  def test_memory_pressure_participates_in_warn_classification
    watcher = Master::Fix::Watcher.allocate
    watcher.instance_variable_set(
      :@thresholds,
      "mem_free_pct" => { "warn" => 30.0, "crit" => 5.0 },
    )

    level = watcher.send(
      :classify,
      load_1m: nil,
      mem_free_pct: 25.0,
      disk_root_pct: nil,
      master_rss_mb: nil,
      master_alive: true,
    )

    assert_equal :warn, level
  end

  def test_shell_output_parsers_return_numeric_pressure_values
    watcher = Master::Fix::Watcher.allocate
    df = <<~DF
      Filesystem  1K-blocks     Used    Avail Capacity  Mounted on
      /dev/sd0a     1032454   812345   158012    84%    /
    DF
    ps = <<~PS
        RSS COMMAND
      262144 falcon serve -b tcp://127.0.0.1:53187
       10240 ruby other.rb
    PS

    assert_equal 1.23, watcher.send(:load_average_1m, "{ 1.23 0.50 0.25 }\n")
    assert_equal 84.0, watcher.send(:disk_percent, df)
    assert_equal 256.0, watcher.send(:master_rss_mb_from_ps, ps)
  end
end
