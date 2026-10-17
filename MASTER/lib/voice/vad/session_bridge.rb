# frozen_string_literal: true

module Master
  module Voice
    class Vad
      # Binds Vad events to Session transitions and Session state to Vad mode.
      # Keeps Vad and Session free of hard references to each other.
      module SessionBridge
        module_function

        def attach(session, vad)
          raise ArgumentError, "session required" unless session
          raise ArgumentError, "vad required" unless vad

          vad.on_event do |event|
            case event.name
            when :speech_start
              if %i[speaking thinking approval].include?(session.state)
                session.interrupt!(reason: :vad_barge_in)
              elsif session.state == :idle || session.state == :interrupted
                session.listening! if session.respond_to?(:listening!)
              end
            when :speech_end
              session.thinking! if session.state == :listening && session.respond_to?(:thinking!)
            end
          end

          if session.respond_to?(:on_event)
            session.on_event do |ev|
              to = ev.respond_to?(:to) ? ev.to : ev[:to]
              case to
              when :speaking, :thinking, :approval
                vad.mode!(:barge_in)
              when :listening, :working, :idle
                vad.mode!(:listening)
                vad.reset! if to == :idle
              end
            end
          end

          session
        end
      end
    end
  end
end
