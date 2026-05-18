# frozen_string_literal: true

module Master
  module Ground
  module ClaudeCodeTasks
  module MobileWebClusters
    GOAL = "Turn mobile-web opportunity clusters into runtime Ruby profiles and audits."

    CLUSTERS = {
      installable_master_pwa: {
        targets: %w[web/public/manifest.json web/app/views/chat/index.html.erb web/public/face.js web/public/visual_bridge.js],
        tasks: [
          "audit manifest/installability and add missing safe fields",
          "add service-worker strategy audit object; do not blindly cache sensitive chats",
          "add reduced-motion, battery, thermal, and offline-shell checks"
        ]
      },
      offline_first_memory: {
        targets: %w[lib/ground/memory_index.rb lib/ground/memory_search.rb lib/trace/session.rb],
        tasks: [
          "add local-first transcript/cache schema draft in Ruby",
          "add offline event queue interface",
          "sync attention context and cluster evidence as local records"
        ]
      },
      browser_local_ai: {
        targets: %w[lib/ground/provider_registry.rb web/public/visual_bridge.js web/public/cluster_miner.js],
        tasks: [
          "add browser_local provider tier to ProviderRegistry",
          "route low-risk classification/labeling to browser-local tier when available",
          "emit provider fallback visual events"
        ]
      },
      mobile_sensor_body: {
        targets: %w[web/public/face.js web/public/face3d_engine.js web/public/visual_bridge.js],
        tasks: [
          "map device orientation to head pose when user grants permission",
          "map haptics to verdict/tool events with accessibility safeguards",
          "add mobile gesture and reduced-motion gates"
        ]
      },
      webgpu_face_runtime: {
        targets: %w[web/public/face3d_engine.js web/public/face3d_renderer.js web/public/face3d_preview.js],
        tasks: [
          "define renderer interface contract before implementing WebGPU",
          "keep canvas renderer as default fallback",
          "add fps and thermal governor before high-density rendering"
        ]
      }
    }.freeze

    REQUIRED_NEW_RUBY = %w[
      lib/design/mobile_web_profiles.rb
      lib/ground/pwa_audit.rb
      lib/ground/offline_queue.rb
    ].freeze

    CONSTRAINTS = [
      "No markdown deliverables.",
      "Do not add service worker behavior that caches secrets or private chat content by default.",
      "Every mobile feature must have accessibility and reduced-motion behavior.",
      "Every browser-local AI hook must be optional and privacy-preserving.",
      "Do not replace existing Face3D identity; add adapters and fallbacks."
    ].freeze

    VERIFY = [
      "ruby -c MASTER/lib/design/mobile_web_profiles.rb",
      "ruby -c MASTER/lib/ground/pwa_audit.rb",
      "ruby -c MASTER/lib/ground/offline_queue.rb",
      "grep -R \"browser_local\" MASTER/lib/ground/provider_registry.rb",
      "grep -R \"reduced-motion\|prefers-reduced-motion\|reduced_motion\" MASTER/web/public MASTER/lib/design MASTER/lib/ground"
    ].freeze
  end
  end
  end
end
