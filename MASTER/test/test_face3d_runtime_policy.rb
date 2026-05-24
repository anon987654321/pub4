# frozen_string_literal: true

require_relative "test_helper"

class TestFace3dRuntimePolicy < Minitest::Test
  def test_desktop_profile_keeps_effects_under_budget
    profile = Master::Rails::Face3dRuntimePolicy.new(pointer: :fine, average_frame_ms: 16.0).profile

    assert_equal 60, profile[:fps_cap]
    assert_equal 2600, profile[:particles]
    assert profile[:effects][:bloom]
    assert profile[:effects][:spatial_repulsion]
  end

  def test_mobile_profile_disables_expensive_effects
    profile = Master::Rails::Face3dRuntimePolicy.new(pointer: :coarse).profile

    assert_equal 30, profile[:fps_cap]
    assert_equal 700, profile[:particles]
    refute profile[:effects][:bloom]
    refute profile[:effects][:spatial_repulsion]
  end

  def test_hidden_profile_throttles_runtime
    profile = Master::Rails::Face3dRuntimePolicy.new(hidden: true).profile

    assert_equal 5, profile[:fps_cap]
    assert_equal 200.0, profile[:frame_budget_ms]
    refute profile[:effects][:oscilloscope]
  end

  def test_audit_rejects_webgpu_before_cpu_fallback
    findings = Master::Rails::Face3dRuntimePolicy.new.audit_source("navigator.gpu.requestAdapter()")

    assert_equal :critical, findings.first.severity
    assert_equal :webgpu, findings.first.field
  end

  def test_audit_flags_parallel_particle_face_runtime
    findings = Master::Rails::Face3dRuntimePolicy.new.audit_source("/particle-face/particle_compute.wgsl")

    assert_equal :runtime_fork, findings.first.field
  end

  def test_degradation_order_is_stable
    assert_equal %i[bloom spatial_repulsion oscilloscope frame_cap particle_count], Master::Rails::Face3dRuntimePolicy.new.degradation_order
  end
end
