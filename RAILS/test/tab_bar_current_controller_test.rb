# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "json"

# brgen's tab bar survives Turbo visits (data-turbo-permanent), so its
# aria-current has to be re-marked after each one. Run in node against
# stand-in links; Stimulus is a bare base class.
class TabBarCurrentControllerTest < Minitest::Test
  CONTROLLER = File.expand_path("../brgen/app/javascript/controllers/tab_bar_current_controller.js", __dir__)
  STIMULUS = %(import { Controller } from "@hotwired/stimulus")

  VISIT = <<~JS
    const link = (href) => ({
      href, attributes: {},
      getAttribute() { return this.href },
      setAttribute(name, value) { this.attributes[name] = value },
      removeAttribute(name) { delete this.attributes[name] }
    })
    const links = [link("/"), link("/communities"), link("/nearby")]
    const listeners = {}

    globalThis.window = { location: { pathname: "/", origin: "https://brgen.no" } }
    globalThis.document = { addEventListener: (type, fn) => { listeners[type] = fn }, removeEventListener() {} }

    const controller = new TabBarCurrent()
    controller.element = { querySelectorAll: () => links }
    controller.connect()

    window.location.pathname = "/nearby"
    listeners["turbo:load"]()
    console.log(JSON.stringify(links.map((l) => l.attributes["aria-current"] ?? null)))
  JS

  def run_page(script)
    source = File.read(CONTROLLER)
    assert source.include?(STIMULUS), "#{CONTROLLER} no longer imports Stimulus through #{STIMULUS.inspect}"
    program = source.sub(STIMULUS, "class Controller {}")
                    .sub("export default class extends Controller", "class TabBarCurrent extends Controller") + script
    out, status = Open3.capture2e("node", "--input-type=module", stdin_data: program)
    assert status.success?, out
    JSON.parse(out.lines.last)
  end

  def test_a_turbo_visit_moves_aria_current_to_the_new_page
    assert_equal [ nil, nil, "page" ], run_page(VISIT)
  end
end
