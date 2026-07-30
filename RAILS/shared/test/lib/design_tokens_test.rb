# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../../../tools/design_tokens"

class DesignTokensTest < Minitest::Test
  FACE_CSS = File.expand_path("../../../../MASTER/web/public/face.css", __dir__)

  def test_face_root_css_emits_anchors
    data = DesignTokens.load.fetch("face_root")
    css = DesignTokens.face_root_css

    assert_includes css, ":root {"
    data.fetch("anchors").each_key do |key|
      assert_includes css, "--#{key.to_s.tr('_', '-')}:", "missing face anchor #{key}"
    end
  end

  def test_face_root_block_has_generated_markers
    block = DesignTokens.face_root_block

    assert_includes block, "BEGIN:generated-face-root"
    assert_includes block, "END:generated-face-root"
    assert_includes block, "generate_face_root_css.rb"
  end

  def test_sync_face_css_updates_drifted_block
    data = DesignTokens.load.fetch("face_root")
    anchors = data.fetch("anchors")
    key = anchors.keys.first
    stale = anchors.fetch(key) == "#ffffff" ? "#000000" : "#ffffff"

    Dir.mktmpdir do |dir|
      path = File.join(dir, "face.css")
      File.write(path, <<~CSS)
        /* BEGIN:generated-face-root — ruby RAILS/tools/generate_face_root_css.rb */
        :root {
          --#{key.to_s.tr('_', '-')}: #{stale};
        }
        /* END:generated-face-root */
      CSS

      assert DesignTokens.sync_face_css!(path)
      body = File.read(path)
      assert_includes body, DesignTokens.face_root_css.lines.grep(/--#{key.to_s.tr('_', '-')}/).first.to_s.strip.split(";").first
      refute_includes body, stale
    end
  end

  def test_sync_face_css_noop_when_in_sync
    skip "face.css missing" unless File.file?(FACE_CSS)

    Dir.mktmpdir do |dir|
      path = File.join(dir, "face.css")
      File.write(path, "#{DesignTokens.face_root_block}\n")
      refute DesignTokens.sync_face_css!(path)
    end
  end

  def test_face_root_drift_detects_mismatch
    Dir.mktmpdir do |dir|
      path = File.join(dir, "face.css")
      File.write(path, <<~CSS)
        /* BEGIN:generated-face-root — ruby RAILS/tools/generate_face_root_css.rb */
        :root { --c-text: #000000; }
        /* END:generated-face-root */
      CSS

      assert DesignTokens.face_root_drift?(path)
    end
  end

  def test_social_tokens_yaml_present
    social = DesignTokens.load.fetch("social")
    %w[bg surface text accent border].each do |key|
      assert social.key?(key), "design_tokens.yml#social missing #{key}"
    end
  end
end
