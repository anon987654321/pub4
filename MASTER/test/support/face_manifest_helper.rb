# frozen_string_literal: true

require "yaml"

# Shared reader for web/config/face_assets.yml.
#
# Four specs used to scrape `javascript_include_tag(*%w[...])` and
# `faceModulesList: %w[...]` straight out of chat/index.html.erb. Those literals
# are gone — the view renders from the manifest — so each spec would otherwise
# grow its own copy of this parsing.
module FaceManifestHelper
  PATH = File.expand_path("../../web/config/face_assets.yml", __dir__).freeze

  module_function

  def face_manifest = @face_manifest ||= YAML.safe_load_file(PATH).freeze

  # The deferred javascript_include_tag list, in load order, as bare names.
  def shell_manifest = Array(face_manifest["shell_manifest"])

  # Modules face.js imports eagerly on the primer tap, in load order.
  def face_eager = Array(face_manifest["face_eager"])
end
