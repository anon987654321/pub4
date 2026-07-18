# frozen_string_literal: true

module Master
  module CLI
    module CommandRegistry
      module_function

      def media_commands(bus: nil)
        {
          "music" => command(:dispatch_music, bus),
        }
      end

      def dispatch_music(bus, ctx: nil)
        args = arg_for(ctx).to_s.strip.downcase
        if args.start_with?("radio")
          publish_radio(bus)
        else
          publish_dilla(bus)
        end
      end

      def publish_dilla(bus)
        bus&.publish("client_action", action: "dilla_bg", label: "J Dilla pocket")
        "Music: Dilla pocket — lo-fi beat on the face canvas. (/music radio for Radio Bergen.)"
      end

      def publish_radio(bus)
        bus&.publish("client_action", action: "radio_open", url: "/radio_bergen", label: "Radio Bergen")
        "Music: Radio Bergen — J Dilla · Flying Lotus · Madlib warp tunnel."
      end
    end
  end
end
