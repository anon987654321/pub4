# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "json"

# A like the server refuses keeps its card, and only a request that never
# reached the server waits in the offline queue.
#
# The test environment turns forgery protection off, so a page there carries no
# csrf-token meta tag, and production refuses a write whose token is stale. Both
# must read as a refusal: a card that leaves the deck, or a like parked in the
# offline queue, looks exactly like a like that was recorded.
#
# The controller runs in node against a page with no token tag. Its two imports
# are the Stimulus base class and the offline queue, and both are replaced with
# recorders, so what is measured is the controller's own branching.
class SwipeControllerCommitTest < Minitest::Test
  CONTROLLER = File.expand_path("../brgen/app/javascript/controllers/swipe_controller.js", __dir__)

  IMPORTS = {
    %(import { Controller } from "@hotwired/stimulus") => "class Controller { constructor(element) { this.element = element } }",
    %(import { enqueueSync } from "pwa/offline_store") => "const queued = []; const enqueueSync = async (entry) => { queued.push(entry) }",
    %(import Haptics from "pub4/haptics") => "const Haptics = { pulse() {} }",
  }.freeze

  PAGE = <<~JS
    const cards = []
    const card = (userId) => ({
      dataset: { userId }, style: {}, classList: { add() {}, remove() {} },
      remove() { cards.splice(cards.indexOf(this), 1) }
    })
    cards.push(card("7"))
    const stack = { querySelectorAll: () => [...cards] }
    const element = { querySelector: (selector) => (selector === "#swipe-stack" ? stack : null) }
    globalThis.document = { querySelector: () => null, getElementById: () => null }
    console.error = () => {}
    const settle = () => new Promise((resolve) => setTimeout(resolve, 450))

    const swipe = async (answer, act) => {
      globalThis.fetch = async () => answer()
      const controller = new SwipeController(element)
      Object.assign(controller, { likeUrlValue: "/like", dislikeUrlValue: "/pass", hasModeValue: false, hasListenUrlValue: false })
      controller.connect()
      await act(controller)
      await settle()
      return { cards: cards.length, queued: queued.length }
    }
  JS

  def run_page(script)
    source = File.read(CONTROLLER)
    IMPORTS.each do |line, stub|
      assert source.include?(line), "#{CONTROLLER} no longer imports through #{line.inspect}; update the stub"
      source = source.sub(line, stub)
    end
    program = source.sub("export default class extends Controller", "class SwipeController extends Controller") +
              PAGE + script
    out, status = Open3.capture2e("node", "--input-type=module", stdin_data: program)
    assert status.success?, out
    JSON.parse(out.lines.last)
  end

  def test_a_refused_like_from_the_button_keeps_the_card_and_queues_nothing
    result = run_page(<<~JS)
      console.log(JSON.stringify(await swipe(() => ({ ok: false, status: 422 }), (c) => c.like())))
    JS

    assert_equal({ "cards" => 1, "queued" => 0 }, result)
  end

  def test_a_refused_drag_keeps_the_card_and_queues_nothing
    result = run_page(<<~JS)
      const drag = async (c) => {
        c.pointerDown({ target: { closest: () => null }, clientX: 0, preventDefault() {} })
        c.pointerMove({ clientX: 200 })
        await c.pointerUp({})
      }
      console.log(JSON.stringify(await swipe(() => ({ ok: false, status: 422 }), drag)))
    JS

    assert_equal({ "cards" => 1, "queued" => 0 }, result)
  end

  def test_a_recorded_like_removes_the_card
    result = run_page(<<~JS)
      console.log(JSON.stringify(await swipe(() => ({ ok: true, status: 200 }), (c) => c.like())))
    JS

    assert_equal({ "cards" => 0, "queued" => 0 }, result)
  end

  # A window-level arrow key is a swipe only when nobody is typing.
  KEY_IN_A_FIELD = <<~JS
    const key = { type: "keydown", target: { closest: (s) => (s.includes("textarea") ? {} : null) } }
    console.log(JSON.stringify(await swipe(() => ({ ok: true, status: 200 }), (c) => c.like(key))))
  JS

  KEY_WITH_A_MODIFIER = <<~JS
    const key = { type: "keydown", altKey: true, target: { closest: () => null } }
    console.log(JSON.stringify(await swipe(() => ({ ok: true, status: 200 }), (c) => c.pass(key))))
  JS

  ANNOUNCED_LIKE = <<~JS
    const region = { textContent: "", dataset: { liked: "Liked %{name}", passed: "Passed" } }
    cards[0].dataset.name = "Kari"
    await swipe(() => ({ ok: true, status: 200 }), (c) => {
      Object.assign(c, { hasAnnouncementTarget: true, announcementTarget: region })
      return c.like()
    })
    console.log(JSON.stringify({ said: region.textContent }))
  JS

  def test_an_arrow_key_typed_into_a_field_leaves_the_card
    assert_equal({ "cards" => 1, "queued" => 0 }, run_page(KEY_IN_A_FIELD))
  end

  def test_an_arrow_key_held_with_a_modifier_leaves_the_card
    assert_equal({ "cards" => 1, "queued" => 0 }, run_page(KEY_WITH_A_MODIFIER))
  end

  def test_a_recorded_like_is_announced_by_name
    assert_equal({ "said" => "Liked Kari" }, run_page(ANNOUNCED_LIKE))
  end

  def test_a_lost_connection_queues_the_like_and_removes_the_card
    result = run_page(<<~JS)
      console.log(JSON.stringify(await swipe(() => { throw new TypeError("Failed to fetch") }, (c) => c.like())))
    JS

    assert_equal({ "cards" => 0, "queued" => 1 }, result)
  end
end
