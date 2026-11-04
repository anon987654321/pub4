# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "json"

# brgen radio's playlist_player_controller, run in node against stand-in
# elements. Stimulus is replaced by a bare base class, so what is measured is
# the controller's own slider values, labels, Media Session handlers and
# listen counting.
class PlaylistPlayerControllerTest < Minitest::Test
  CONTROLLER = File.expand_path(
    "../brgen_radio/playlist/app/javascript/controllers/playlist_player_controller.js", __dir__
  )
  STIMULUS = %(import { Controller } from "@hotwired/stimulus")

  PAGE = <<~JS
    const element = (extra = {}) => ({
      attributes: {}, listeners: {}, style: {}, textContent: "", classList: { add() {}, toggle() {} },
      setAttribute(name, value) { this.attributes[name] = value },
      addEventListener(type, handler) { (this.listeners[type] ||= []).push(handler) },
      ...extra
    })
    const handlers = {}
    const posts = []
    globalThis.window = { addEventListener() {}, MediaMetadata: class {} }
    const mediaSession = { setActionHandler: (action, fn) => { handlers[action] = fn } }
    Object.defineProperty(globalThis, "navigator", { value: { mediaSession } })
    globalThis.document = { querySelector: () => null }
    globalThis.fetch = async (url, options) => { posts.push(JSON.parse(options.body).track_id); return { ok: true } }

    const player = (values = {}) => {
      const audio = element({ duration: 245, currentTime: 83, paused: true, src: "a.mp3" })
      const controller = new PlaylistPlayer()

      Object.assign(controller, {
        hasAudioTarget: true, audioTarget: audio, hasScrubTarget: true, scrubTarget: element(),
        hasPlayBtnTarget: true, playBtnTarget: element(), hasWaveformTarget: false, hasEmbedTarget: false,
        hasPlayIconTarget: false, hasCurrentTimeTarget: false, hasDurationTarget: false, hasScrubFillTarget: false,
        queueItemTargets: [], trackIdValue: "1", titleValue: "", showArtworkValue: true,
        playLabelValue: "Spill av", pauseLabelValue: "Pause", openLabelValue: "Åpne",
        positionLabelValue: "%{current} av %{total}", fallbackTitleLabelValue: "Bergen", ...values
      })

      controller.connect()
      return controller
    }
    const play = (controller) => {
      const { listeners } = controller.audioTarget
      listeners.play.forEach((handler) => handler())
    }
  JS

  SLIDER = <<~JS
    const controller = player()
    console.log(JSON.stringify(controller.scrubTarget.attributes))
  JS

  SKIP_BUTTONS = <<~JS
    const controller = player()
    const steps = []
    controller.next = () => steps.push("next")
    controller.previous = () => steps.push("previous")
    handlers.nexttrack()
    handlers.previoustrack()
    console.log(JSON.stringify({ steps, label: controller.playBtnTarget.textContent }))
  JS

  LISTENS = <<~JS
    const controller = player()
    play(controller)
    play(controller)
    controller.trackIdValue = "2"
    play(controller)
    await new Promise((resolve) => setTimeout(resolve, 10))
    console.log(JSON.stringify({ posts }))
  JS

  def run_page(script)
    source = File.read(CONTROLLER)
    assert source.include?(STIMULUS), "#{CONTROLLER} no longer imports Stimulus through #{STIMULUS.inspect}"
    program = source.sub(STIMULUS, "class Controller {}")
                    .sub("export default class extends Controller", "class PlaylistPlayer extends Controller") +
              PAGE + script
    out, status = Open3.capture2e("node", "--input-type=module", stdin_data: program)
    assert status.success?, out
    JSON.parse(out.lines.last)
  end

  def test_the_scrub_slider_speaks_the_position_in_seconds
    attributes = run_page(SLIDER)

    assert_equal "245", attributes["aria-valuemax"]
    assert_equal "83", attributes["aria-valuenow"]
    assert_equal "1:23 av 4:05", attributes["aria-valuetext"]
  end

  def test_lock_screen_skip_buttons_walk_the_queue_and_labels_follow_the_locale
    result = run_page(SKIP_BUTTONS)

    assert_equal %w[next previous], result["steps"]
    assert_equal "Spill av", result["label"]
  end

  def test_each_track_loaded_records_one_listen
    assert_equal({ "posts" => %w[1 2] }, run_page(LISTENS))
  end
end
