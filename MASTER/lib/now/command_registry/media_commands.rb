# frozen_string_literal: true

module Master
  module Now
    module CommandRegistry
      module_function

      def media_commands(bus: nil)
        {
          "dilla" => command(:dispatch_dilla, bus),
          "radio" => command(:dispatch_radio, bus),
        }
      end

      def dispatch_dilla(bus, ctx: nil)
        bus&.publish("client_action", action: "dilla_bg", label: "J Dilla pocket")
        "Dilla pocket — lo-fi beat on the face canvas. (Swing 88 BPM, ducked under TTS.)"
      end

      def dispatch_radio(bus, ctx: nil)
        bus&.publish("client_action", action: "radio_open", url: "/radio_bergen", label: "Radio Bergen")
        "Opening Radio Bergen — J Dilla · Flying Lotus · Madlib warp tunnel."
      end
    end
  end
end