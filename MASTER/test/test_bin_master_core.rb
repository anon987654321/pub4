# frozen_string_literal: true

require_relative "test_helper"
require "open3"
require "rbconfig"

# bin/master-core is the fold and nothing else, and bin/dogfood reads its exit
# status as the kernel smoke. It exited 0 on every run, including the ones where
# the fold spent all forty turns being refused, so the smoke said "ok" whatever
# happened. The scripted no-op cannot earn proof, so the constitution must
# refuse its done; these pin both halves of that.
class TestBinMasterCore < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def run_core(prelude = "")
    script = "#{prelude}; load File.join(#{ROOT.inspect}, 'bin', 'master-core')"
    Open3.capture2e(RbConfig.ruby, "-I#{File.join(ROOT, 'lib')}", "-e", script, "--",
                    "--max-turns", "6", "smoke", chdir: ROOT)
  end

  def test_the_no_op_fold_is_refused_done_and_exits_zero
    out, status = run_core

    assert status.success?, out
    assert_includes out, "master-core: max_turns turns=6"
    assert_includes out, "done refused without evidence"
  end

  def test_a_no_op_that_completes_fails_the_smoke
    out, status = run_core('require "master"; Master::Core::Proof.define_method(:proved?) { true }')

    refute status.success?, out
    assert_includes out, "master-core: complete"
  end
end
