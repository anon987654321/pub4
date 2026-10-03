# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "pathname"

class VisualSystemContractTest < Minitest::Test
  ROOT = Pathname.new(File.expand_path("..", __dir__))

  VISUAL_FIELD = ROOT.join("shared/frontend/visual_field.js")
  VISUAL_SURFACE = ROOT.join("shared/frontend/visual_surface_controller.js")
  GRAVITY_FIELD = ROOT.parent.join("MASTER/web/public/gravity_field.js")
  IMPORTMAP = ROOT.join("shared/config/importmap_baseline.rb")
  SOCIAL_BOOT = ROOT.join("shared/frontend/stimulus_boot_social.js")
  BRGEN_LAYOUT = ROOT.join("brgen/app/views/layouts/application.html.erb")
  AMBER_LAYOUT = ROOT.join("amber/app/views/layouts/application.html.erb")
  RADIO = ROOT.join("brgen/app/javascript/radio_brgen_tunnel.js")

  NODE_HARNESS = <<~JS
    import fs from "node:fs"
    import assert from "node:assert/strict"

    const source = fs.readFileSync(process.env.PUB4_VISUAL_FIELD, "utf8")
    const events = []

    globalThis.window = {
      innerWidth: 1200,
      innerHeight: 800,
      devicePixelRatio: 2,
      dispatchEvent(event) {
        events.push(event)
        return true
      }
    }
    globalThis.CustomEvent = class {
      constructor(name, options = {}) {
        this.type = name
        this.detail = options.detail || {}
      }
    }
    globalThis.document = {
      hidden: false,
      documentElement: { dataset: {}, style: {} }
    }
    globalThis.performance = { now: () => 1000 }
    globalThis.matchMedia = () => ({ matches: false })
    globalThis.getComputedStyle = () => ({ getPropertyValue: () => "" })

    const module_url = "data:text/javascript," + encodeURIComponent(source)
    const { normalizeVisual, publishVisual, VisualField } = await import(module_url)

    const zero = normalizeVisual({
      activity: 0,
      entropy: 0,
      confidence: 0,
      arousal: 0,
      focus: 0,
      bass: 0,
      mid: 0,
      high: 0,
      beat: 0
    })

    assert.deepEqual(
      {
        activity: zero.activity,
        entropy: zero.entropy,
        confidence: zero.confidence,
        arousal: zero.arousal,
        focus: zero.focus,
        bass: zero.bass,
        mid: zero.mid,
        high: zero.high,
        beat: zero.beat
      },
      {
        activity: 0,
        entropy: 0,
        confidence: 0,
        arousal: 0,
        focus: 0,
        bass: 0,
        mid: 0,
        high: 0,
        beat: 0
      }
    )

    const inherited = normalizeVisual({ arousal: 0.7 })
    assert.equal(inherited.activity, 0.7)

    const published = publishVisual("radio:beat", { beat: 1, bass: 0 })
    assert.equal(published.name, "radio:beat")
    assert.equal(published.beat, 1)
    assert.equal(published.bass, 0)
    assert.equal(events.length, 1)
    assert.equal(events[0].type, "pub4:visual")

    const context = {
      clearRect() {},
      fillRect() {},
      setTransform() {},
      beginPath() {},
      moveTo() {},
      lineTo() {},
      stroke() {}
    }

    const canvas = {
      clientWidth: 1200,
      clientHeight: 800,
      style: {},
      setAttribute() {},
      getContext() { return context },
      parentElement: null
    }

    const surfaces = {
      master: "orb",
      social: "terrain",
      dating: "pair",
      luxury: "ambient",
      radio: "tunnel",
      mannequin: "mannequin"
    }

    for (const [surface, topology] of Object.entries(surfaces)) {
      const field = new VisualField({ canvas, surface })
      assert.equal(field.topology, topology)
      assert.ok(field.points.length > 0)
      field.frame(1016)
      assert.ok([...field.points].every(Number.isFinite))
      field.destroy()
    }

    const field = new VisualField({ canvas, surface: "social" })
    field.signal({ topology: "pair", activity: 0, beat: 0, bass: 0 })
    assert.equal(field.topology, "pair")
    assert.ok(field.activity < 0.12)
    field.destroy()

    console.log("visual_field: ok")
  JS

  def test_visual_field_runtime_contract
    env = { "PUB4_VISUAL_FIELD" => VISUAL_FIELD.to_s }
    out, err, status = Open3.capture3(env, "node", "--input-type=module", "-e", NODE_HARNESS)
    assert status.success?, "node visual field harness failed:\n#{out}\n#{err}"
    assert_match(/visual_field: ok/, out)
  end

  def test_master_gravity_field_is_deterministic_and_reactive
    source = GRAVITY_FIELD.read
    assert_includes source, "GOLDEN_ANGLE"
    assert_includes source, "master:visual"
    assert_includes source, "master:emotion"
    assert_includes source, "gravity:signal"
    refute_includes source, "Math.random"
  end

  def test_shared_surface_controller_covers_every_surface_signal
    source = VISUAL_SURFACE.read
    %w[
      master:visual
      master:emotion
      pub4:visual
      amber:wardrobe-change
      radio:audio
      master
      social
      dating
      luxury
      radio
    ].each { |token| assert_includes source, token }
  end

  def test_shared_importmap_and_social_boot_register_the_field
    assert_includes IMPORTMAP.read, 'pin "pub4/visual_field", to: "visual_field.js"'
    assert_includes IMPORTMAP.read, 'pin "pub4/visual_surface", to: "visual_surface_controller.js"'
    assert_includes SOCIAL_BOOT.read, 'import VisualSurface from "pub4/visual_surface"'
    assert_includes SOCIAL_BOOT.read, 'application.register("visual-field", VisualSurface)'
  end

  def test_brgen_and_amber_mount_the_shared_surface
    assert_includes BRGEN_LAYOUT.read, "visual-field"
    assert_includes AMBER_LAYOUT.read, "visual-field"
  end

  def test_radio_publishes_into_the_shared_visual_contract
    source = RADIO.read
    assert_includes source, 'import { publishVisual } from "pub4/visual_field"'
    assert_includes source, 'publishVisual("radio:audio"'
    assert_includes source, 'publishVisual("radio:track"'
  end

  def test_shared_visual_field_remains_the_single_particle_contract
    source = VISUAL_FIELD.read
    assert_includes source, "pub4:visual"
    refute_match(/Math\.random\s*\(/, source)
    assert_includes source, "GOLDEN_ANGLE"
  end
end