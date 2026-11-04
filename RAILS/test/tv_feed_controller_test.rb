# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "json"

# brgen tv's vertical feed controller, run in node against stand-in elements.
# Stimulus is a bare base class and Turbo's stream renderer appends items, so
# what is measured is the controller's paging, sound labels and autoplay
# choice.
class TvFeedControllerTest < Minitest::Test
  CONTROLLER = File.expand_path("../brgen_radio/tv/app/javascript/controllers/tv_feed_controller.js", __dir__)
  STIMULUS = %(import { Controller } from "@hotwired/stimulus")

  PAGE = <<~JS
    const button = () => ({ attributes: {}, textContent: "Lyd", setAttribute(k, v) { this.attributes[k] = v } })
    const video = () => ({
      muted: true, played: 0, controls: false, pause() {}, addEventListener() {},
      play() { this.played += 1; return Promise.resolve() }
    })
    const item = () => { const v = video(); return { video: v, dataset: {}, querySelector: () => v } }

    const fetched = []
    let pageSizes = []
    let calm = false

    globalThis.IntersectionObserver = class {
      constructor(callback) { this.callback = callback }
      observe(target) { this.target = target }
      disconnect() {}
    }
    globalThis.requestAnimationFrame = (fn) => fn()
    globalThis.window = { location: { origin: "https://tv.brgen.no" }, matchMedia: () => ({ matches: calm }) }
    globalThis.document = { querySelector: () => null }

    const feed = (count) => {
      const controller = new TvFeed()

      const items = Array.from({ length: count }, item)
      const append = () => items.push(...Array.from({ length: pageSizes.shift() ?? 0 }, item))
      window.Turbo = { renderStreamMessage: append }
      globalThis.fetch = async (url) => { fetched.push(url); return { ok: true, text: async () => "" } }

      Object.defineProperty(controller, "itemTargets", { get: () => items })
      Object.assign(controller, {
        hasNextUrlValue: true, nextUrlValue: "/feed.turbo_stream?offset=10", signedInValue: false,
        soundButtonTargets: [button(), button()], videoTargets: [],
        soundOnLabelValue: "Lyd", soundOffLabelValue: "Lyd av"
      })

      controller.connect()
      return controller
    }
    const reachEnd = async (controller) => {
      controller.endWatcher.callback([{ isIntersecting: true }])
      await new Promise((resolve) => setTimeout(resolve, 5))
    }
  JS

  PAGING = <<~JS
    pageSizes = [10, 0]
    const controller = feed(10)
    await reachEnd(controller)
    await reachEnd(controller)
    console.log(JSON.stringify({ fetched, next: controller.nextUrlValue }))
  JS

  SOUND = <<~JS
    const controller = feed(1)
    controller.toggleSound({ currentTarget: controller.soundButtonTargets[0] })
    const [first, second] = controller.soundButtonTargets
    const labels = [first.textContent, second.textContent]
    console.log(JSON.stringify({ pressed: second.attributes["aria-pressed"], labels }))
  JS

  CALM = <<~JS
    calm = true
    const controller = feed(1)
    const [only] = controller.itemTargets
    controller.visibility.callback([{ target: only, isIntersecting: true }])
    console.log(JSON.stringify({ played: only.video.played, controls: only.video.controls }))
  JS

  def run_page(script)
    source = File.read(CONTROLLER)
    assert source.include?(STIMULUS), "#{CONTROLLER} no longer imports Stimulus through #{STIMULUS.inspect}"
    program = source.sub(STIMULUS, "class Controller {}")
                    .sub("export default class extends Controller", "class TvFeed extends Controller") +
              PAGE + script
    out, status = Open3.capture2e("node", "--input-type=module", stdin_data: program)
    assert status.success?, out
    JSON.parse(out.lines.last)
  end

  def test_the_next_page_starts_where_the_feed_ends_and_an_empty_page_stops_paging
    result = run_page(PAGING)

    assert_equal [ "/feed.turbo_stream?offset=10", "/feed.turbo_stream?offset=20" ], result["fetched"]
    assert_equal "", result["next"]
  end

  def test_sound_state_and_label_reach_every_button
    result = run_page(SOUND)

    assert_equal "true", result["pressed"]
    assert_equal [ "Lyd av", "Lyd av" ], result["labels"]
  end

  def test_a_reader_asking_for_less_motion_gets_a_play_button_not_autoplay
    assert_equal({ "played" => 0, "controls" => true }, run_page(CALM))
  end
end
