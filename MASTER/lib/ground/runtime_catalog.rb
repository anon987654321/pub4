# frozen_string_literal: true

require_relative "../voice/aesthetic"

module Master
  module Ground
    # Machine-readable runtime catalog stored in data/runtime.yml.
    # Replaces prose docs/ for invariants, UI philosophy, events, enhancements, etc.
    class RuntimeCatalog
      CATALOG_PATH = File.join(Master::ROOT, "data", "runtime.yml").freeze
      SECTIONS = %w[
        invariants ui_philosophy event_registry provider_economy
        cognitive_spine face_enhancements micro_interactions
        platform_topology collaboration repo_ecology
        routing_architecture face3d_migration style_guides face_research
      ].freeze

      @cache = {}

      class << self
        def load(section)
          key = section.to_s
          @cache[key] ||= catalog.fetch(key, {})
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

        def face_research
          load("face_research")
        end

        def web_boot_payload
          sources = web_boot_sources
          runtime_cfg = load("runtime")
          philosophy = ui_philosophy

          {
            topologies_path: "/runtime/topologies",
            enhancements_pending_count: enhancements.count { |item| item["status"].to_s == "pending" },
            enhancements: Array(runtime_cfg["enhancements"]),
            vertical_timbre: philosophy["vertical_timbre"] || {},
            ui_philosophy: runtime_cfg["ui_philosophy"] || {},
            micro_interactions:,
            event_registry:,
            visual_limits: sources[:visual]["visual"] || sources[:visual],
            tts_config: sources[:tts],
            topologies: sources[:topologies],
            face_research:,
          }
        end

        def web_boot_sources
          {
            topologies: Master.load_yaml(Master.data_path("topologies.yml"), default: {}),
            # data/ops/visual.yml was deleted on purpose in 68ca272e0: it had
            # drifted on all five values against visual_governor.js, which is
            # now the one place the limits live. The read outlived it and
            # printed "load_yaml: No such file" on every boot and every test
            # run. The key stays — the browser payload and
            # test_ground_runtime_catalog both expect it — and is empty,
            # because that is what the source is.
            visual: {},
            tts: Master.load_yaml(Master.data_path("tts.yml"), default: {}),
          }
        end

        # Inline in chat shell only — keeps first paint off the ~30KB full catalog parse.
        def web_boot_payload_minimal
          runtime_cfg = load("runtime")
          # Path was "OPENBSD/openbsd/vm_resource.yml" — a doubled segment. The
          # file is at OPENBSD/vm_resource.yml, so every load printed
          # "load_yaml: No such file or directory" and fell through to {} via the
          # rescue, silently defaulting falcon_worker_budget to FALCON_COUNT
          # instead of the VM's configured master_falcon_workers limit.
          vm = Master.load_yaml(File.join(Master::REPO_ROOT, "OPENBSD", "vm_resource.yml"), default: {}) rescue {}
          pending = enhancements.count { |item| item["status"].to_s == "pending" }
          falcon_workers = Integer(vm.dig("limits", "master_falcon_workers") || ENV.fetch("FALCON_COUNT", "2"))

          {
            topologies_path: "/runtime/topologies",
            config_path: "/runtime/config",
            enhancements_pending_count: pending,
            enhancements: Array(runtime_cfg["enhancements"]),
            falcon_worker_budget: falcon_workers,
            aesthetic: Master::Voice::Aesthetic.mode,
          }
        end

        def clear_cache!
          @cache = {}
          @catalog = nil
        end

        private

        def catalog
          @catalog ||= Master.load_yaml(CATALOG_PATH, default: {})
        end
      end
    end
  end
end
