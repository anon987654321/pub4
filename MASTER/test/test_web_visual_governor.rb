# frozen_string_literal: true

require "minitest/autorun"
require_relative "support/face_manifest_helper"

class VisualGovernorSpec < Minitest::Test
  include FaceManifestHelper

  ROOT = File.expand_path("..", __dir__)
  # layouts/application.html.erb is dead for this purpose — ChatController#index
  # renders `layout: false` (web/CLAUDE.md); chat/index.html.erb is the real page.
  ENTRYPOINT = File.join(ROOT, "web", "app", "views", "chat", "index.html.erb")

  # The limits and the hidden-tab pause are behaviour, driven in
  # web/test/visual_limits.test.mjs. What stays here is what the page template
  # says, which is text: visual_governor, which patches
  # window.requestAnimationFrame, is in the deferred boot manifest, so it has run
  # before the primer tap can import face.js, and face.js is never tagged eagerly.
  def test_entrypoint_loads_visual_governor_in_deferred_manifest_before_any_tap
    source = File.read(ENTRYPOINT)
    assert_includes shell_manifest, "visual_governor"
    # source-assertion: ok — how the template loads face.js is a property of its text.
    refute_match(/<script[^>]+src=["'][^"']*face\.js/, source)
    # source-assertion: ok — the same property, from the other side.
    assert_includes source, 'import("<%= asset_path("face.js") %>")'
  end
end
