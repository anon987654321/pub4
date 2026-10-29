# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../../lib/shared/contracts"
# On vm23 __shared sits under /home/<app>, so a path four levels up lands on /home/MASTER and the
# test never loaded; Shared::Contracts finds the checkout that holds MASTER in either layout.
require Shared::Contracts.tool_path("design_tokens")
require Shared::Contracts.tool_path("rails/build_face_css")

class DesignTokensTest < Minitest::Test
  FACE_CSS = File.join(Shared::Contracts.root, "RAILS", "master", "public", "face.css")

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
    assert_includes block, "design_tokens.rb generate_face_root_css"
  end

  def test_sync_face_css_updates_drifted_block
    data = DesignTokens.load.fetch("face_root")
    anchors = data.fetch("anchors")
    key = anchors.keys.first
    stale = anchors.fetch(key) == "#ffffff" ? "#000000" : "#ffffff"

    Dir.mktmpdir do |dir|
      path = File.join(dir, "face.css")
      File.write(path, <<~CSS)
        /* BEGIN:generated-face-root — ruby MASTER/tools/rails/generate_face_root_css.rb */
        :root {
          --#{key.to_s.tr('_', '-')}: #{stale};
        }
        /* END:generated-face-root */
      CSS

      assert DesignTokens.sync_face_css!(path)
      body = File.read(path)
      assert_includes body,
DesignTokens.face_root_css.lines.grep(/--#{key.to_s.tr('_', '-')}/).first.to_s.strip.split(";").first
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
        /* BEGIN:generated-face-root — ruby MASTER/tools/rails/generate_face_root_css.rb */
        :root { --c-text: #000000; }
        /* END:generated-face-root */
      CSS

      assert DesignTokens.face_root_drift?(path)
    end
  end

  # RAILS/UI_REFINEMENTS.md carried "Token CSS auto-gen test fail-on-drift" as a
  # follow-up for generate_face_root_css.rb. Every drift predicate below already
  # existed and every test above proved it works — on a fixture in a tmpdir. Nothing
  # asserted the committed files, so the generator could go unrun for weeks and the
  # suite stayed green while face.css and MASTER's tokens disagreed.
  #
  # These three run against the real tree. The remedy is in each message, because a
  # drift failure is a "you forgot to run the generator", not a bug to debug.
  def test_committed_face_css_matches_design_tokens
    skip "face.css missing" unless File.file?(FACE_CSS)

    drift = DesignTokens.face_root_drift?(FACE_CSS)

    assert_nil drift, "RAILS/master/public/face.css :root has drifted from " \
                      "generated design projection (#{drift}) — run " \
                      "`ruby MASTER/tools/rails/generate_face_root_css.rb`"
  end

  def test_committed_face_css_matches_ordered_source_modules
    assert_equal MasterFaceStylesheet.render, File.read(FACE_CSS, encoding: "UTF-8"),
                 "MASTER face CSS differs from source modules — run ruby MASTER/tools/rails/build_face_css.rb"
  end

  def test_committed_dialect_scss_anchors_match_design_tokens
    drift = DesignTokens.scss_anchor_drift?

    assert_nil drift, "_dialect_tokens.scss has drifted from MASTER tokens (#{drift}) — " \
                      "run `ruby MASTER/tools/rails/sync_dialect_tokens.rb` or the documented sync"
  end

  def test_committed_dialect_maps_match_design_tokens
    drift = DesignTokens.dialect_token_drift

    assert_empty drift, "dialect token maps have drifted from MASTER tokens:\n  #{Array(drift).join("\n  ")}"
  end

  def test_generated_token_artifact_matches_master
    # The generated artifact uses YAML aliases, as tokens.yml does; DesignTokens.load allows them.
    artifact = YAML.safe_load_file(File.expand_path("../../design_tokens.yml", __dir__), aliases: true)
    assert_equal DesignTokens.load, artifact
  end

  # The face carries brgen's family :root verbatim, so its var(--text) and
  # var(--font) are brgen's. face_bg stays a literal because the views print it
  # into theme-color, which is why it is held equal to the family ground here.
  def test_face_embeds_the_family_root_and_shares_its_ground
    css = File.read(FACE_CSS, encoding: "UTF-8")
    tokens = DesignTokens.load

    assert_includes css, DesignTokens.family_tokens_block
    assert_operator css.index("BEGIN:generated-family-tokens"), :<, css.index("BEGIN:generated-face-root")
    assert_equal tokens.fetch("social").fetch("bg"), tokens.fetch("face_root").fetch("face_bg")
    refute_match(/--text-secondary:\s*var\(--text-secondary\)/, DesignTokens.static_tokens_css)
  end

  def test_committed_static_tokens_css_matches_master_projection
    path = File.join(DesignTokens::ROOT, "RAILS/__shared/public/styles/tokens.css")

    assert_equal DesignTokens.static_tokens_css, File.read(path),
                 "public tokens.css drifted from MASTER tokens; run ruby MASTER/tools/rails/build_all_css.rb"
  end

  def test_all_scss_files_includes_nested_engine_sources_and_excludes_artifacts
    Dir.mktmpdir do |root|
      host = File.join(root, "RAILS/amber/app/assets/stylesheets/application.scss")
      engine = File.join(root, "RAILS/brgen_dating/app/assets/stylesheets/_vertical.scss")
      vendor = File.join(root, "RAILS/brgen_dating/app/assets/stylesheets/vendor/_vendor.scss")
      build = File.join(root, "RAILS/brgen_dating/app/assets/stylesheets/builds/_built.scss")

      [host, engine, vendor, build].each do |path|
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, ".fixture { color: var(--text); }\n")
      end

      assert_equal [host, engine].sort, DesignTokens.all_scss_files(root)
    end
  end

  def test_social_tokens_yaml_present
    social = DesignTokens.load.fetch("social")
    %w[bg surface text accent border].each do |key|
      assert social.key?(key), "MASTER tokens#social missing #{key}"
    end
  end

# amber keeps its own luxury palette. The exemption names four properties in
# one stylesheet; anything wider would let a sync repaint another app.
def test_only_amber_owns_four_luxury_properties_and_the_check_still_passes
  amber = File.join(DesignTokens::ROOT, "RAILS/amber/app/assets/stylesheets/application.scss")
  brgen = File.join(DesignTokens::ROOT, "RAILS/brgen/app/assets/stylesheets/application.scss")

  %w[luxury-bg luxury-text luxury-muted luxury-border].each do |var|
    assert DesignTokens.app_owned?(amber, var), "amber should own --#{var}"
    refute DesignTokens.app_owned?(brgen, var), "brgen must not own --#{var}"
  end
  refute DesignTokens.app_owned?(amber, "luxury-accent"), "the exemption must stay at four properties"
  # Two amber stylesheets own the same four properties; the exemption is the four names.
  assert_equal 4, DesignTokens::APP_OWNED_PALETTE.values.flatten.uniq.size
  assert_empty DesignTokens.dialect_token_drift
end
  def test_signal_and_stillness_is_single_sourced_for_both_css_generators
    identity = DesignTokens.load.fetch("visual_identity")

    assert_equal "signal_and_stillness", identity.fetch("name")
    assert_equal "#C8F55F", identity.fetch("signal")
    assert_equal "#101010", identity.fetch("signal_ink")
    assert_equal "#50630A", identity.fetch("signal_on_light")
    assert_equal "var(--pub4-signal)", DesignTokens.load.dig("face_root", "anchors", "c_accent")

    shared = DesignTokens.static_tokens_css
    face = DesignTokens.face_root_css
    %w[pub4-signal pub4-signal-ink pub4-signal-on-light].each do |name|
      assert_includes shared, "--#{name}:"
      assert_includes face, "--#{name}:"
    end
    assert_includes face, "--c-accent: var(--pub4-signal);"
  end

  def test_signal_ink_has_adequate_contrast_for_its_intended_surfaces
    identity = DesignTokens.load.fetch("visual_identity")
    ratio = lambda do |foreground, background|
      luminance = lambda do |hex|
        rgb = hex.delete("#").scan(/../).map { |channel| channel.to_i(16) / 255.0 }
        linear = rgb.map { |value| value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055)**2.4 }
        0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
      end
      values = [luminance.call(foreground), luminance.call(background)].sort.reverse
      (values[0] + 0.05) / (values[1] + 0.05)
    end

    assert_operator ratio.call(identity.fetch("signal"), identity.fetch("signal_ink")), :>=, 7.0
    assert_operator ratio.call(identity.fetch("signal_on_light"), "#FFFFFF"), :>=, 4.5
    assert_operator ratio.call(identity.fetch("signal_on_light"), "#EFEFEF"), :>=, 4.5
  end

  def test_face_signal_does_not_overwrite_shared_dialect_accent
    scss = File.read(DesignTokens::DIALECT_PATH, encoding: "UTF-8")

    assert_includes scss, "$c-accent: oklch(78% 0.10 300),"
    assert_includes DesignTokens.face_root_css, "--c-accent: var(--pub4-signal);"
    assert_nil DesignTokens.scss_anchor_drift?
  end

  def test_display_size_is_generated_from_the_visual_identity_token
    identity = DesignTokens.load.fetch("visual_identity")
    css = DesignTokens.static_tokens_css

    assert_equal "clamp(40px, 6vw, 88px)", identity.fetch("display_size")
    assert_includes css, "--text-display: #{identity.fetch('display_size')};"
  end

  def test_identity_contrast_floors_are_operator_owned_tokens
    floors = DesignTokens.load.fetch("visual_identity").fetch("contrast")

    assert_operator floors.fetch("signal_on_ink_min"), :>=, 7.0
    assert_operator floors.fetch("signal_on_white_min"), :>=, 4.5
    assert_operator floors.fetch("signal_on_paper_min"), :>=, 4.5
  end

end
