# frozen_string_literal: true

module Master
  module Builder
    module_function

    # Full boot: all 6 plugins, AI stack, pipeline.
    def build(root: Dir.pwd)
      Master.configure_providers!
      infra = build_infrastructure(root)
      ai = build_ai_stack(root, infra)
      pipeline, gateway = build_pipeline_and_gateway(root, infra, ai)
      infra.merge(ai).merge(pipeline:, gateway:, root:)
    end

    # Scan-only boot: trace + judge only — no LLM, no loop, no reach network.
    # Used by MASTER_SCAN_ONLY=1 and CI environments.
    def build_scan_only(root: Dir.pwd)
      config      = Ground::Config.new(root)
      boot_config = config.freeze_boot
      trace       = Plugins::Trace.boot(root:, config:)
      bus         = trace[:bus]
      code_index  = Judge::CodeIndex.new(root:, event_bus: bus)
      scanner     = Plugins::Judge.configure(nil, root:, bus:)
      trace.merge(config:, boot_config:, code_index:, scanner:, root:)
    end

    def build_infrastructure(root)
      config      = Ground::Config.new(root)
      config["model"] ||= Master.default_model
      boot_config = config.freeze_boot
      trace  = Plugins::Trace.boot(root:, config:)
      loop_c = Plugins::Loop.boot(root:, config:, bus: trace[:bus])
      reach  = Plugins::Reach.boot(root:, config:, bus: trace[:bus])
      ground = Plugins::Ground.boot(root:, config:, homeostat: loop_c[:homeostat])

      bus        = trace[:bus]
      renderer   = Voice::Renderer.new(config:)
      code_index = Judge::CodeIndex.new(root:, event_bus: bus)
      code_index.build_async
      bus.subscribe("tool:after") { |ev| code_index.reindex(ev[:path]) if ev[:path] }
      diag = Trace::Diag.new(homeostat: loop_c[:homeostat], breaker: reach[:breaker], logging: trace[:logging])

      { config:, boot_config:, renderer:, code_index:, diag: }
        .merge(trace).merge(loop_c).merge(reach).merge(ground)
    end

    def build_ai_stack(root, infra)   = Plugins::Judge.build_ai(root, infra)
    def build_pipeline_and_gateway(root, infra, ai) = Plugins::Now.build_pipeline(root, infra, ai)

  end
end
