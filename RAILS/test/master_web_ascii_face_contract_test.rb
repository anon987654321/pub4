# frozen_string_literal: true

require "minitest/autorun"
require "digest"
require "yaml"

# The web face draws the terminal's ASCII face. The renderer itself is held to the
# Ruby frames by RAILS/master_web/test/face_ascii.test.mjs; this reads the source as text
# and holds what surrounds it: the generated runtime still matches its parts, the boot
# manifest keeps its order with the new script in it, the shell reads the terminal's
# wordmark and prompt glyphs from the one token block, and the type is mono for the face
# and the shell with no serif anywhere.
class MasterWebAsciiFaceContractTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  WEB = File.join(ROOT, "RAILS", "master_web")
  PUBLIC = File.join(WEB, "public")
  SOURCES = %w[face.part1.txt face.part2.txt face.part3.txt face_speech_runtime.js face_speech_playback.js face.part5.txt].freeze

  def read(*path) = File.read(File.join(*path))
  def view = @view ||= read(WEB, "app", "views", "chat", "index.html.erb")
  def manifest = @manifest ||= YAML.safe_load_file(File.join(WEB, "config", "face_assets.yml"))
  def tokens = @tokens ||= YAML.safe_load_file(File.join(ROOT, "MASTER", "data", "tokens.yml"), aliases: true)
  def ascii = tokens.dig("tokens", "face_interface", "ascii")

  def test_the_generated_runtime_names_its_parts_by_their_current_digest
    runtime = read(PUBLIC, "face.runtime.js")
    listed = runtime[/FACE_RUNTIME_SOURCES = (\[.*?\]);/, 1]
    refute_nil listed, "face.runtime.js lost its source list"
    named = listed.scan(/"([^"?]+)\?v=([0-9a-f]{10})"/)

    assert_equal SOURCES, named.map(&:first), "the runtime concatenates six sources in this order; run rails assets:build_face_runtime"
    named.each do |name, digest|
      assert_equal Digest::SHA256.file(File.join(PUBLIC, name)).hexdigest[0, 10], digest, "#{name} changed since face.runtime.js was built; run rails assets:build_face_runtime"
    end
    assert_includes runtime, "do not edit by hand"
  end

  def test_the_ascii_script_loads_before_the_fallback_and_after_the_boot_script
    early = manifest.fetch("shell_early")

    assert_equal "face_ascii.js", early.first
    assert_operator early.index("face_ascii.js"), :<, early.index("face_2d_fallback.js")
    boot = view.index("function go()")
    ascii_tag = view.index('asset_path("face_ascii.js")')
    fallback_tag = view.index('asset_path("face_2d_fallback.js")')

    assert_operator boot, :<, ascii_tag
    assert_operator ascii_tag, :<, fallback_tag
    assert_match(/<script src="<%= asset_path\("face_ascii\.js"\) %>" defer><\/script>/, view)
  end

  def test_particle_kernel_still_leads_every_face_consumer_and_ascii_is_not_an_eager_module
    assert_equal ["particle_kernel.js"], manifest.fetch("shell_blocking")
    assert_operator view.index('asset_path("particle_kernel.js")'), :<, view.index('id="primer"')
    refute_includes manifest.fetch("face_eager"), "face_ascii.js", "it is a shell script; the bundle is not rebuilt for it"
    bundle = read(PUBLIC, "face.modules.bundle.js")

    refute_includes bundle, "MASTER_FACE_ASCII"
  end

  def test_face_stays_the_public_global_and_ascii_adds_no_second_one
    assert_includes read(PUBLIC, "face.part5.txt"), "window.MASTER_FACE = {"
    runtime = SOURCES.map { |name| read(PUBLIC, name) }.join
    refute_match(/MASTERFace\b/, runtime)
    refute_match(/MASTERFace\b/, read(PUBLIC, "face_ascii.js"))
  end

  def test_the_runtime_draws_ascii_on_a_canvas_that_has_no_webgl_context
    part1 = read(PUBLIC, "face.part1.txt")
    part3 = read(PUBLIC, "face.part3.txt")

    assert_match(/_hasWebGL = !_asciiEngine && /, part1, "ascii mode must not create a WebGL context on #face")
    assert_match(/if \(_asciiEngine && cv && !renderer\)/, part1)
    assert_match(/!renderer && !asciiView/, part3)
    assert_match(/if \(asciiView\) \{\n    drawAsciiFace\(t\);/, part3)
    assert_includes part1, "?face_mode=3d"
    refute_match(/getElementById\(["']face["']\)\s*\.getContext/, read(PUBLIC, "face_2d_fallback.js"))
  end

  def test_the_configured_face_shortcuts_control_laws_and_overlay_separately
    source = read(PUBLIC, "face_ascii.js")
    handler = source[/function onKeydown\(event\) \{.*?^  \}/m]
    refute_nil handler, "the configured face shortcuts must have a testable handler"
    law_handler = handler[/if \(pressed === lawKey\) \{.*?^    \}/m]
    refute_nil law_handler, "the law shortcut must have its own branch"

    assert_includes view, "window.MASTER_FACE_LAW_FIELD"
    assert_includes source, "lawFieldVisible = lawFieldConfig.enabled !== false"
    assert_includes law_handler, "setLawField(!lawFieldVisible)"
    assert_includes law_handler, "Constitutional law glyphs visible"
    assert_includes law_handler, "Constitutional law glyphs hidden"
    assert_includes law_handler, "field.laws"
    assert_includes law_handler, "in priority order"
    assert_includes law_handler, 'getElementById("ui-status")',
                     "the law shortcut must announce its change through an existing live region"
    refute_includes law_handler, "setGlyphMode",
                     "the law key must not change the whole ASCII overlay mode"
    refute_includes law_handler, "update(",
                     "the law key must not create a second overlay canvas"
    assert_includes handler, "field.overlay_toggle_key"
    assert_includes handler, "setGlyphMode(!glyphMode)"
    assert_includes handler, "ASCII face mode enabled"
    assert_includes handler, "ASCII face overlay enabled"
  end

  def test_the_renderer_and_its_frames_are_plain_ascii_without_braille
    source = read(PUBLIC, "face_ascii.js")

    refute_match(/[\u2800-\u28ff]/, source)
    assert_match(/\A[\t\n\x20-\x7e]*\z/, source, "face_ascii.js holds only printable ASCII")
    assert_equal " .:-=+*#%@", ascii.fetch("chars")
  end

  def test_every_number_the_view_needs_is_in_the_contract_the_page_receives
    assert_match(/window\.MASTER_FACE_CONTRACT = <%= raw Master\.tokens\.fetch\("face_interface", \{\}\)\.to_json %>/, view)
    web = ascii.fetch("web")

    assert_kind_of Integer, web.fetch("rows")
    assert_equal 3, web.fetch("tone").size
    assert_equal 2, web.fetch("font").size
    source = read(PUBLIC, "face_ascii.js")
    %w[rows font tone].each { |key| assert_includes source, "web.#{key}" }
    budget = tokens.dig("tokens", "face_interface", "spatial", "budget")
    %w[active_fps idle_fps reduced_motion_fps].each { |key| assert_includes budget.keys, key }
  end

  def test_the_shell_wears_the_terminals_wordmark_and_prompt_glyphs
    assert_equal 3, ascii.fetch("wordmark").size
    assert_match(/<pre id="wordmark" class="wordmark" aria-hidden="true"><%= Master::Face::Contract\.wordmark\.join\("\\n"\) %><\/pre>/, view)
    assert_match(/<span class="pp" aria-hidden="true"><%= Master::Face::Contract\.glyph\(:input\) %><\/span>/, view)
    chat = read(PUBLIC, "chat.js")

    assert_includes chat, "MASTER_FACE_CONTRACT?.ascii?.prompt?.[name]"
    assert_includes chat, "promptGlyph(role === 'user' ? 'input' : 'output')"
    refute_match(/master\$|\$ /, chat[/function appendMsg.*?\n\}\n/m].to_s)
    %w[en nb].each { |loc| refute_match(/prompt_user/, read(WEB, "config", "locales", "#{loc}.yml")) }
    assert_equal({ "input" => "|-", "continuation" => "\\_", "output" => "/" }, ascii.fetch("prompt"))
  end

  def test_the_brand_mark_is_left_to_its_own_font
    css = read(PUBLIC, "face.css")

    assert_match(/--font-logo: system-ui/, css)
    assert_match(/font: 800 clamp\(15px,3\.8vw,24px\)\/1 var\(--font-logo\)/, css)
    assert_includes view, '<span class="brand-text"><%= mark %></span>'
  end

  def test_type_is_mono_for_the_face_and_shell_and_never_serif
    %w[face.css chat_upload.css].each do |name|
      css = read(PUBLIC, name)
      bare = css.gsub(/ui-sans-serif|sans-serif/i, "")

      refute_match(/\bserif\b/i, bare, "#{name}: no serif generic")
      refute_match(/georgia|garamond|palatino|cambria|times new roman|didot|bodoni/i, css, "#{name}: no named serif face")
    end
    css = read(PUBLIC, "face.css")
    shell = css.scan(/^(#chat-log|\.message|\.msg-body)\s*\{[^}]*\}/m).size

    assert_operator shell, :>=, 3
    css.scan(/^(?:#chat-log|\.message|\.msg-body|\.message\.(?:user|assistant) \.msg-prompt)\s*\{[^}]*\}/m).each do |block|
      refute_match(/font(?:-family)?:[^;]*var\(--font-brand\)/, block, "shell rule keeps the sans brand font:\n#{block}")
    end
  end
end
