# frozen_string_literal: true

require "yaml"

# Reader for config/face_assets.yml — the one manifest of face JavaScript.
#
# Deliberately a plain module with no Rails dependency beyond the path, so the
# rc.d precompile digest and the boot contract tests can enumerate the same set
# the view renders. See the YAML header for why the set was unenumerable before.
module FaceAssets
  PATH = File.expand_path("../../config/face_assets.yml", __dir__).freeze

  MODULE_GROUPS = %w[face_eager face_runtime_deferred face_vision_deferred].freeze
  SHELL_GROUPS = %w[shell_early shell_manifest shell_late].freeze

  module_function

  def manifest
    @manifest ||= YAML.safe_load_file(PATH).freeze
  end

  def group(name) = Array(manifest[name.to_s]).freeze

  def singletons = manifest.fetch("singletons").freeze

  # Imported the moment the primer tap resolves.
  def eager = group("face_eager")

  # Everything face.js needs a resolved URL for: the eager imports plus the two
  # lazily-imported groups, which look their paths up in the same map.
  def module_names = MODULE_GROUPS.flat_map { |name| group(name) }.uniq.freeze

  # Every file this manifest claims the shell loads, as bare filenames. The
  # include_tag group carries no extension, so it gets one here.
  def all_filenames
    names = MODULE_GROUPS.flat_map { |name| group(name) } + singletons.values
    names += group("shell_blocking") + group("shell_boot") + group("shell_early") + group("shell_late")
    names += group("shell_manifest").map { |name| "#{name}.js" }
    names.uniq.sort.freeze
  end
end
