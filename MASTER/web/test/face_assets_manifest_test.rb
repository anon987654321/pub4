# frozen_string_literal: true

require "test_helper"

# config/face_assets.yml is only a single source of truth if nothing can load a
# face asset without appearing in it. These tests are that guarantee.
class FaceAssetsManifestTest < ActiveSupport::TestCase
  VIEW = Rails.root.join("app/views/chat/index.html.erb")
  PUBLIC = Rails.root.join("public")

  def view_source = @view_source ||= File.read(VIEW)

  test "every file the manifest names exists in public/" do
    missing = FaceAssets.all_filenames.reject { |name| PUBLIC.join(name).file? }

    assert_empty missing, "manifest names files that are not in public/"
  end

  # The eager list and the path map used to be two hand-written literals
  # repeating the same twelve names. The map is derived now; this pins that.
  test "the path map is a superset of the eager list" do
    assert_operator FaceAssets.module_names.size, :>, FaceAssets.eager.size
    assert_empty FaceAssets.eager - FaceAssets.module_names
    assert_equal FaceAssets.module_names.uniq, FaceAssets.module_names, "no duplicate module entries"
  end

  # The trap this file exists to close: javascript_include_tag takes bare names,
  # so a `grep foo.js` over the repo misses live assets. face_state.js was read
  # as dead for exactly this reason.
  test "shell_manifest entries are extensionless and real" do
    FaceAssets.group("shell_manifest").each do |name|
      refute_match(/\.js\z/, name, "javascript_include_tag takes bare names")
      assert PUBLIC.join("#{name}.js").file?, "#{name}.js is missing from public/"
    end
  end

  test "every script the view loads by asset_path is in the manifest" do
    referenced = view_source.scan(/asset_path\("([\w.]+\.js)"\)/).flatten.uniq
    # face.js is imported lazily on the primer tap, not loaded by the shell.
    unmanaged = referenced - FaceAssets.all_filenames - %w[face.js boot_fsm.js]

    assert_empty unmanaged, "index.html.erb loads these outside config/face_assets.yml"
  end

  test "the view renders its ordered manifest from the yaml, not a literal list" do
    assert_match(/javascript_include_tag\(\*FaceAssets\.group\("shell_manifest"\)/, view_source)
    refute_match(/javascript_include_tag\(\*%w\[/, view_source)
  end

  test "the position-sensitive tags in the view match shell_early and shell_late" do
    literal = view_source.scan(/<script src="<%= asset_path\("([\w.]+\.js)"\) %>" defer><\/script>/).flatten

    assert_equal (FaceAssets.group("shell_early") + FaceAssets.group("shell_late")).sort, literal.sort
  end

  # particle_kernel is the one script that must not be deferred: every deferred
  # ecology/worker module and the post-primer face import assume
  # window.ParticleKernel already exists.
  test "shell_blocking is loaded synchronously and before the primer" do
    FaceAssets.group("shell_blocking").each do |name|
      tag = %(<script src="<%= asset_path("#{name}") %>"></script>)
      assert_includes view_source, tag, "#{name} must load synchronously"
      assert_operator view_source.index(tag), :<, view_source.index('id="primer"')
    end
  end

  # face_2d_fallback is deliberately after the inline boot script: a blocking
  # script above it would delay the tap wiring the primer depends on.
  test "face_2d_fallback still loads after the inline boot script" do
    boot = view_source.index("function go()")
    fallback = view_source.index('asset_path("face_2d_fallback.js")')

    assert boot && fallback
    assert_operator fallback, :>, boot
  end
end
