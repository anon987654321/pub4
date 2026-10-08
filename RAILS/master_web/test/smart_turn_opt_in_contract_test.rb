# frozen_string_literal: true

require "minitest/autorun"
require "pathname"

# Smart Turn costs about 21MB on first use: a 12.9MB WASM runtime and an 8.3MB
# ONNX model. It is opt-in, so none of that may sit on the critical path. The
# only door to those bytes is public/smart_turn.js, which fetches them after a
# visitor switches the feature on. A <script src>, a preload, a manifest entry
# or a second module naming the URLs would ship them to everyone.
class SmartTurnOptInContractTest < Minitest::Test
  ROOT = Pathname(__dir__).join("..").expand_path
  # A quoted file name, not a property: face_vision sets dataset.wasm.
  HEAVY = %r{onnxruntime|\.(?:onnx|wasm)(?=["'`?#])|/models/smart-turn}

  def test_no_view_or_asset_manifest_names_the_heavy_files
    files = Dir[ROOT.join("app/views/**/*").to_s].select { |path| File.file?(path) } +
            [ROOT.join("config/face_assets.yml").to_s]
    offenders = files.select { |path| File.read(path).match?(HEAVY) }

    assert_empty offenders.map { |path| Pathname(path).relative_path_from(ROOT).to_s }
  end

  def test_only_smart_turn_js_reaches_for_them
    sources = Dir[ROOT.join("public/*.{js,mjs,txt}").to_s]
    offenders = sources.reject { |path| File.basename(path) == "smart_turn.js" }
                       .select { |path| File.read(path).match?(HEAVY) }

    assert_operator sources.size, :>, 20, "the scan must read the face sources, not an empty glob"
    assert_match HEAVY, ROOT.join("public/smart_turn.js").read, "the pattern must still see the one file allowed to match"
    assert_empty offenders.map { |path| File.basename(path) }
  end

  def test_the_fetch_waits_for_an_explicit_switch
    src = ROOT.join("public/smart_turn.js").read

    assert_includes src, %(localStorage.getItem("master:smart-turn") === "1")
    assert_match(/export async function warmUp\(\) \{\n\s+if \(!smartTurnEnabled\(\)\) return false;/, src)
  end
end
