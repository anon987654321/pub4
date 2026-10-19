# frozen_string_literal: true

require_relative "test_helper"

class TestDoctorTimeoutContract < Minitest::Test
  def test_doctor_routes_probes_through_the_bounded_process_runner
    source = File.read(File.join(Master::ROOT, "tools", "doctor.rb"))

    assert_includes source, 'require_relative "../lib/io/exec"'
    assert_includes source, "Master::Io::Exec.capture2e(*argv, timeout:)"
    refute_includes source, "Open3.capture2e(*argv)"
  end
end
