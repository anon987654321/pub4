# frozen_string_literal: true

module FaceAssetsHelper
  FACE_MODULE_NAMES = %w[
    face_particles.js face_audio_bridge.js face_tts_bridge.js face_expression_bridge.js
    face_blendshape_bridge.js face_council_multi.js face_phosphor_trail.js face_offscreen_ecology.js
    face_micro_interactions.js face_perf_guards.js face_brutalist.js
    face_semantics.js face_minimal_ui.js face_loops_music.js face_loops_nudge.js
  ].freeze

  FACE_PRELOAD_MODULES = %w[
    face_blendshape_bridge.js face3d_preview.js face3d_engine.js face3d_renderer.js
    face3d_geometry.js face3d_support.js
  ].freeze

  def master_face_asset_paths
    paths = {
      threeModule: asset_path("three.face.module.js"),
      face3dPreview: asset_path("face3d_preview.js"),
      face3dEngine: asset_path("face3d_engine.js"),
      face3dRenderer: asset_path("face3d_renderer.js"),
      face3dGeometry: asset_path("face3d_geometry.js"),
      face3dSupport: asset_path("face3d_support.js"),
      faceParts: (1..5).map { |part| asset_path("face.part#{part}.txt") },
      faceModulesList: FACE_MODULE_NAMES.first(11),
      faceModules: FACE_MODULE_NAMES.index_with { |name| asset_path(name) }
    }
    runtime = Rails.root.join("public/face.runtime.js")
    paths[:faceRuntime] = asset_path("face.runtime.js") if File.file?(runtime)
    paths
  end

  def master_face_import_map
    {
      "/face3d_geometry.js" => asset_path("face3d_geometry.js"),
      "/face3d_support.js" => asset_path("face3d_support.js")
    }
  end

  def master_sw_precache_paths
    %w[
      offline.html face.css face.js chat.js chat_actions.js face_state.js visual_bridge.js
      master_events.js shortcut_sheet.js particle_kernel.js three.face.module.js
      manifest.json icon.png
    ].map { |name| asset_path(name) }.uniq
  end
end