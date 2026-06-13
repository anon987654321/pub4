# frozen_string_literal: true

module Master
  module Rails
    class Face3dRuntimePolicy
      EFFECT_ORDER = %i[bloom spatial_repulsion oscilloscope frame_cap particle_count].freeze
      DEFAULT_FRAME_BUDGET_MS = 16.7
      MOBILE_FRAME_BUDGET_MS = 33.4
      HIDDEN_FRAME_BUDGET_MS = 200.0
      MOBILE_PARTICLES = 700
      DESKTOP_PARTICLES = 2600

      Finding = Data.define(:field, :message, :severity)

      def initialize(pointer: :fine, hidden: false, average_frame_ms: DEFAULT_FRAME_BUDGET_MS)
        @pointer = pointer
        @hidden = hidden
        @average_frame_ms = average_frame_ms.to_f
      end

      def profile
        return hidden_profile if @hidden
        desktop_profile
      end

      def degradation_order = EFFECT_ORDER

      def audit_source(source)
        findings = []
        findings << Finding.new(:webgpu, "WebGPU must not be introduced before CPU fallback is complete", :critical) if source.include?("navigator.gpu")
        findings << Finding.new(:sync_gpu_readback, "synchronous GPU readback is forbidden in the Face3D render path", :critical) if source.include?("mapAsync") && source.include?("requestAnimationFrame")
        findings << Finding.new(:runtime_fork, "Face3D changes must use the existing face3d_engine / face3d_preview path", :high) if source.include?("particle-face")
        findings << Finding.new(:visibility, "preview loop should listen for visibilitychange", :medium) unless source.include?("visibilitychange")
        findings
      end

      private

      def desktop_profile
        {
          fps_cap: @average_frame_ms > 24 ? 30 : 60,
          frame_budget_ms: DEFAULT_FRAME_BUDGET_MS,
          particles: DESKTOP_PARTICLES,
          effects: {
            bloom: @average_frame_ms <= 24,
            spatial_repulsion: @average_frame_ms <= 24,
            oscilloscope: true,
          },
        }
      end

      def mobile_profile
        {
          fps_cap: 30,
          frame_budget_ms: MOBILE_FRAME_BUDGET_MS,
          particles: MOBILE_PARTICLES,
          effects: {
            bloom: false,
            spatial_repulsion: false,
            oscilloscope: true,
          },
        }
      end

      def hidden_profile
        {
          fps_cap: 5,
          frame_budget_ms: HIDDEN_FRAME_BUDGET_MS,
          particles: MOBILE_PARTICLES,
          effects: {
            bloom: false,
            spatial_repulsion: false,
            oscilloscope: false,
          },
        }
      end
    end
  end
end
