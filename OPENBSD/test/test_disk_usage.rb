# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/disk_usage"

class TestDiskUsage < Minitest::Test
  OPENBSD = <<~DF
    Filesystem  1K-blocks      Used     Avail Capacity iused   ifree  %iused  Mounted on
    /dev/sd0a     1012974    137446    824880    14%    2915  152331     2%   /
    /dev/sd0h     9912846   9420000    -2000    100%  120000   10000    92%   /home
    /dev/sd0e     1498334     40000   1383418     3%    1000  200000     0%   /var
  DF

  def test_a_full_filesystem_fails_by_blocks_and_inodes
    lines = Deploy::DiskUsage.failures(OPENBSD)

    assert_equal ["disk: /home blocks 100% used", "disk: /home inodes 92% used"], lines
  end

  def test_a_healthy_box_passes
    healthy = OPENBSD.lines.reject { |line| line.include?("/home") }.join

    assert_empty Deploy::DiskUsage.failures(healthy)
  end

  # A df that changed its columns must fail loudly, not pass having read nothing.
  def test_an_unreadable_df_is_a_failure
    refute_empty Deploy::DiskUsage.failures("")
    refute_empty Deploy::DiskUsage.failures("Filesystem Size Used\n/dev/x 1 1\n")
  end

  def test_this_hosts_df_parses
    out = IO.popen(["df", "-ik"], err: File::NULL, &:read)
    skip "no df here" if out.to_s.empty?

    refute(Deploy::DiskUsage.failures(out, limit: 101).any? { |line| line.include?("column") })
  end
end
