# frozen_string_literal: true

require "application_system_test_case"

# Two scripts failed in the browser: the radio tunnel module asked
# radio_brgen_visual for an export it does not have, and StimulusReflex threw
# on the refusal brgen gives a signed-out visitor's reflex channel.
class ScriptLoadErrorsTest < ApplicationSystemTestCase
  include CityHostSystemTest

  setup do
    Brgen::CitySeed.sync! if City.table_exists? && !City.exists?(domain: "brgen.no")
  end

  test "the radio tunnel module loads" do
    visit_city(nil, "/")
    loaded = page.evaluate_async_script(<<~JS)
      const done = arguments[arguments.length - 1]
      import("radio_brgen_tunnel")
        .then((tunnel) => done(typeof tunnel.RadioBrgen === "function" && tunnel.MODES.length > 0 ? "loaded" : "partial"))
        .catch((error) => done(String(error)))
    JS

    assert_equal "loaded", loaded
  end

  # A reflex controller subscribes on the consumer the Stimulus application
  # carries; the refusal is ActionCable's reject for that subscription, the
  # call the socket makes when the server answers reject_subscription.
  test "a refused reflex subscription throws nothing" do
    visit_city(nil, "/")
    outcome = using_wait_time(20) { page.evaluate_async_script(<<~JS) }
      const done = arguments[arguments.length - 1]
      Promise.all([ import("@rails/actioncable"), import("controllers/application_controller") ])
        .then(([ cable, { default: ReflexController } ]) => {
          const consumer = cable.createConsumer()
          window.Stimulus.consumer = consumer
          window.Stimulus.register("reflex-probe", class extends ReflexController {})
          document.body.insertAdjacentHTML("beforeend", "<div data-controller='reflex-probe'></div>")
          const refuse = () => {
            const subscription = consumer.subscriptions.subscriptions[0]
            if (!subscription) return setTimeout(refuse, 50)
            try {
              consumer.subscriptions.reject(subscription.identifier)
              done("refused quietly")
            } catch (error) {
              done(String(error))
            }
          }
          refuse()
        })
        .catch((error) => done(`setup failed: ${error}`))
    JS

    assert_equal "refused quietly", outcome
  end
end
