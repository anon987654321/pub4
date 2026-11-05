# frozen_string_literal: true

require "test_helper"
require_relative "stimulus_node"

# toast_controller's own source under node: a confirmation leaves after the
# family's one toast duration, the 4000 ms shared/_toast gives the shared
# toast, and an alert never schedules its leaving.
class ToastControllerTest < ActiveSupport::TestCase
  include StimulusNode

  # The shared engine sits beside the app as __shared here, shared on the box.
  SHARED_TOAST = [ Rails.root.join("../__shared/app/views/shared/_toast.html.erb"),
                   Rails.root.join("../shared/app/views/shared/_toast.html.erb") ].freeze

  SCRIPT = <<~JS
    const delays = []
    globalThis.setTimeout = (fn, ms) => { delays.push(ms); return delays.length }
    globalThis.clearTimeout = () => {}

    const values = Subject.values.delay
    const confirmation = new Subject({ dataset: {}, classList: { add() {} } })
    confirmation.persistValue = false
    confirmation.delayValue = values.default
    confirmation.connect()

    const alert = new Subject({ dataset: {}, classList: { add() {} } })
    alert.persistValue = true
    alert.delayValue = values.default
    alert.connect()

    console.log(JSON.stringify({ delays }))
  JS

  test "a confirmation leaves after the shared toast duration and an alert stays" do
    shared = SHARED_TOAST.find(&:exist?).read[/fetch\(:delay, (\d+)\)/, 1]

    assert_equal [ shared.to_i ], run_stimulus("toast", SCRIPT)["delays"]
  end
end
