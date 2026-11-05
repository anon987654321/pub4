# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "json"

# The tab bar survives Turbo visits (data-turbo-permanent), so its
# aria-current has to be re-marked after each one. scroll-chrome owns the bar
# and does it. Run in node against stand-in links; Stimulus is a bare base
# class and pub4/onboarding never lets the coach prompt.
class ScrollChromeCurrentTabTest < Minitest::Test
  CONTROLLER = File.expand_path("../__shared/frontend/scroll_chrome_controller.js", __dir__)
  STIMULUS = %(import { Controller } from "@hotwired/stimulus")
  ONBOARDING = %(import { mayPrompt, YIELD_EVENT } from "pub4/onboarding")

  VISIT = <<~JS
    const link = (href) => ({
      href, attributes: {},
      getAttribute() { return this.href },
      setAttribute(name, value) { this.attributes[name] = value },
      removeAttribute(name) { delete this.attributes[name] }
    })
    const links = [link("/"), link("/communities"), link("/nearby")]
    const listeners = {}

    globalThis.window = {
      location: { pathname: "/", origin: "https://brgen.no" },
      addEventListener() {}, removeEventListener() {}
    }
    globalThis.document = {
      documentElement: { classList: { toggle() {}, contains: () => true } },
      addEventListener: (type, fn) => { listeners[type] = fn },
      removeEventListener() {}
    }

    const controller = new ScrollChrome()
    controller.element = { scrollTop: 0, addEventListener() {}, removeEventListener() {} }
    controller.hasBarTarget = true
    controller.barTarget = { querySelectorAll: () => links, setAttribute() {}, removeAttribute() {} }
    controller.connect()
    const first = links.map((l) => l.attributes["aria-current"] ?? null)

    window.location.pathname = "/nearby"
    listeners["turbo:load"]()
    console.log(JSON.stringify([first, links.map((l) => l.attributes["aria-current"] ?? null)]))
  JS

  def run_page(script)
    source = File.read(CONTROLLER)
    [ STIMULUS, ONBOARDING ].each do |line|
      assert source.include?(line), "#{CONTROLLER} no longer imports #{line.inspect}"
    end

    program = source.sub(STIMULUS, "class Controller {}")
                    .sub(ONBOARDING, %(const mayPrompt = () => false; const YIELD_EVENT = "pub4:yield"))
                    .sub("export default class extends Controller", "class ScrollChrome extends Controller") + script
    out, status = Open3.capture2e("node", "--input-type=module", stdin_data: program)
    assert status.success?, out

    JSON.parse(out.lines.last)
  end

  def test_a_turbo_visit_moves_aria_current_to_the_new_page
    first, after_visit = run_page(VISIT)

    assert_equal [ "page", nil, nil ], first
    assert_equal [ nil, nil, "page" ], after_visit
  end
end
