# frozen_string_literal: true

require "minitest/autorun"

class BootFsmSpec < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  def read(path)
    File.read(File.join(ROOT, path))
  end

  def test_boot_fsm_defines_states_and_transitions
    source = read("web/public/boot_fsm.js")

    %w[INIT PRIMER ASSETS FACE VOICE READY RECOVERING ERROR].each do |state|
      assert_includes source, state
    end
    assert_includes source, "TRANSITIONS"
    assert_includes source, "master:boot-state"
    assert_includes source, "dataset.bootState"
  end

  def test_boot_fsm_exposes_master_namespace
    source = read("web/public/boot_fsm.js")

    assert_includes source, "window.MASTER = window.MASTER || {}"
    assert_includes source, "window.MASTER.boot = api"
    assert_includes source, "MASTER_BOOT_FSM"
  end

  def test_chat_index_loads_boot_fsm_before_primer_boot
    index = read("web/app/views/chat/index.html.erb")
    fsm_idx = index.index('asset_path("boot_fsm.js")')
    boot_idx = index.index("function go()")

    assert fsm_idx, "boot_fsm.js not referenced in chat index"
    assert boot_idx, "primer boot script missing"
    assert_operator fsm_idx, :<, boot_idx
    assert_includes index, "MASTER?.boot?.transition?.('PRIMER'"
    assert_includes index, "MASTER?.boot?.transition?.('ASSETS'"
    assert_includes index, "MASTER?.boot?.transition?.('ERROR'"
  end

  def test_container_gate_signals_boot_fsm
    source = read("web/public/container_gate.js")

    assert_includes source, 'MASTER?.boot?.signal?.("container_ready"'
    assert_includes source, 'MASTER?.boot?.transition?.("RECOVERING"'
  end

  def test_face_runtime_signals_boot_fsm_on_face_and_voice
    part1 = read("web/public/face.part1.txt")
    part5 = read("web/public/face.part5.txt")

    assert_includes part1, "MASTER?.boot?.signal?.('face_ready'"
    assert_includes part1, "MASTER?.boot?.signal?.('renderer_failed'"
    assert_includes part5, "MASTER?.boot?.transition?.('FACE'"
    assert_includes part5, "MASTER?.boot?.transition?.('VOICE'"
    assert_includes part5, "MASTER?.boot?.signal?.('voice_ready'"
  end
end
