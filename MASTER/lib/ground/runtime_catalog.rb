# frozen_string_literal: true

module Master
  module Ground
    # Machine-readable runtime catalog over data/runtime/*.yml.
    # Replaces prose docs/ for invariants, UI philosophy, events, enhancements, etc.
    class RuntimeCatalog
      RUNTIME_DIR = File.join(Master::ROOT, "data", "runtime").freeze
      SECTIONS = %w[
        invariants ui_philosophy event_registry provider_economy
        cognitive_spine face_enhancements micro_interactions
        platform_topology collaboration repo_ecology
        routing_architecture face3d_migration style_guides
      ].freeze

      @cache = {}

      class << self
        def load(section)
          key = section.to_s
          @cache[key] ||= begin
            path = File.join(RUNTIME_DIR, "#{key}.yml")
            Master.load_yaml(path, default: {})
          end
        end

        def all
          SECTIONS.to_h { |section| [section, load(section)] }
        end

        def enhancements(area: nil, tier: nil)
          items = Array(load("face_enhancements")["enhancements"])
          items = items.select { |item| item["area"].to_s == area.to_s } if area
          items = items.select { |item| item["tier"].to_s == tier.to_s } if tier
          items
        end

        def micro_interactions
          Array(load("micro_interactions")["interactions"])
        end

        def micro_interaction(id)
          micro_interactions.find { |item| item["id"].to_s == id.to_s }
        end

        def event_registry
          load("event_registry")
        end

        def invariants
          load("invariants")
        end

        def ui_philosophy
          load("ui_philosophy")
        end

        def face3d_migration
          load("face3d_migration")
        end

        def web_boot_payload
          topologies = Master.load_yaml(Master.data_path("topologies.yml"), default: {})
          visual = Master.load_yaml(Master.data_path("ops", "visual.yml"), default: {})
          tts = Master.load_yaml(Master.data_path("tts.yml"), default: {})
          runtime_cfg = Master.load_yaml(File.join(RUNTIME_DIR, "runtime.yml"), default: {})
          philosophy = ui_philosophy
          pending = enhancements.count { |item| item["status"].to_s == "pending" }

          {
            topologies_path: "/runtime/topologies",
            enhancements_pending_count: pending,
            enhancements: Array(runtime_cfg["enhancements"]),
            vertical_timbre: philosophy["vertical_timbre"] || {},
            ui_philosophy: runtime_cfg["ui_philosophy"] || {},
            micro_interactions: micro_interactions,
            event_registry: event_registry,
            visual_limits: visual["visual"] || visual,
            tts_config: tts,
            topologies: topologies,
          }
        end

        def clear_cache!
          @cache = {}
        end
      end
    end
  end
end
