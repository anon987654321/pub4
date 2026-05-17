# frozen_string_literal: true

module Master
  module Builder
    MUTATING_TOOLS = %w[WriteFile StrReplace AstEdit Shell].freeze

    module_function

    # Full boot: all 6 plugins, AI stack, pipeline.
    def build(root: Dir.pwd)
      Master.configure_providers!
      infra = build_infrastructure(root)
      ai = Plugins::Judge.build_ai(root, infra)
      pipeline, gateway = Plugins::Now.build_pipeline(root, infra, ai)
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
      bus.subscribe("tool:after") do |ev|
        next unless ev[:path] && MUTATING_TOOLS.include?(ev[:tool].to_s.split("::").last)
        code_index.reindex(ev[:path])
      end
      diag     = Trace::Diag.new(homeostat: loop_c[:homeostat], breaker: reach[:breaker], logging: trace[:logging])
      pressure = PressureEngine.new(event_bus: bus)
      bus.subscribe("*") do |ev|
        event_name = ev[:event] || ev["event"] || ev[:type] || ev["type"] || "event"
        next if event_name.to_s.start_with?("pressure:")
        pressure.ingest(event: event_name, payload: ev)
      rescue StandardError => e
        Swallow.log(e, context: "builder.pressure_engine", event_bus: bus)
      end

      { config:, boot_config:, renderer:, code_index:, diag:, pressure: }
        .merge(trace).merge(loop_c).merge(reach).merge(ground)
    end

  end
end
