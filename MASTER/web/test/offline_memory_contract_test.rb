# frozen_string_literal: true

require "minitest/autorun"
require "pathname"

# Contract for the offline_first_memory scaffold.
# Does not boot a browser; asserts the module and SW bridge exist and expose
# the documented surface so the next wiring step cannot silently delete them.
#
# mobile_web_opportunities.yml was deleted 2026-08-11 (dead cluster registry).
# Do not resurrect it here — the live contract is the JS + SW files.
class OfflineMemoryContractTest < Minitest::Test
  ROOT = Pathname(__dir__).join("..").expand_path

  def read(rel)
    ROOT.join(rel).read
  end

  def test_offline_memory_module_exists
    path = ROOT.join("public/offline_memory.js")
    assert path.file?, "public/offline_memory.js must exist"
    src = path.read
    assert_includes src, "OfflineMemory"
    assert_includes src, "enqueueTurn"
    assert_includes src, "enqueueEvent"
    assert_includes src, "recentTranscript"
    assert_includes src, "pendingEvents"
    assert_includes src, "drainEvents"
    assert_includes src, "indexedDB"
    assert_includes src, "master_offline"
  end

  def test_sw_exposes_offline_drain_bridge
    src = read("public/sw.js")
    assert_includes src, "offline:drain"
    assert_includes src, "offline:drain-ack"
  end
end
