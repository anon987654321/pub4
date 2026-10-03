# frozen_string_literal: true

require "minitest/autorun"

class VpsRunRemoteContractTest < Minitest::Test
  SOURCE = File.read(File.expand_path("../bin/vps_run_remote.sh", __dir__), encoding: "UTF-8")

  def test_nested_vm_target_is_shell_quoted
    assert_includes SOURCE, "quoted_vm=${(q)VM}"
    refute_match(/scp .* \$\{VM\}:/, SOURCE)
    refute_match(/ssh .* \$\{VM\} /, SOURCE)
  end

  def test_nested_remote_log_path_is_shell_quoted
    assert_includes SOURCE, "quoted_log=${(q)REMOTE_LOG}"
    refute_includes SOURCE, "> ${REMOTE_LOG} 2>&1"
  end
end
