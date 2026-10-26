# frozen_string_literal: true

require_relative "env"
require_relative "face_server"
require_relative "bridge"
require_relative "personality"
require_relative "session"
require_relative "ambient"

module Master
  module Mobile
    # The phone host: one face socket, one session, and every utterance handed
    # to MASTER with the person's preferences and the recent turns before it.
    class Host
      NAME = /\bcall me\s+(\w+)/i

      attr_reader :face, :session, :personality, :ambient

      def initialize(root:, config: Mobile.config, bridge: nil, ambient: nil)
        @root = File.expand_path(root)
        @session = Session.new(root: @root)
        @personality = Personality.new(root: @root)
        @bridge = bridge || Bridge.new(root: @root, timeout_s: config.dig("bridge", "utterance_timeout_s") || 120)
        @ambient = ambient || Ambient.new(config:)
        @face = FaceServer.new(root: @root, run_id: @session.id, config:, on_utterance: method(:handle_utterance))
      end

      def start!
        @session.touch!
        @face.start!
      end

      def stop! = @face.stop!

      def serve_loop
        loop { @face.serve_once }
      end

      def handle_utterance(text, _source = "face")
        @personality.remember!("name", text[NAME, 1]) if text.match?(NAME)
        prompt = prompt_for(text)
        @session.append_turn!(role: "user", text:)
        result = @bridge.submit_utterance!(prompt)
        reply = result.ok? ? result.output.to_s.strip : "error: #{result.error}"
        reply = "(no output)" if reply.empty?
        @session.append_turn!(role: "master", text: reply)
        reply
      end

      # One press of listen: hear one utterance, answer it, and say the answer aloud.
      def listen_and_answer
        heard = @ambient.listen_once
        return { "ok" => false, "error" => heard.error } unless heard.ok?
        return { "ok" => false, "error" => "heard nothing" } if heard.text.empty?

        reply = handle_utterance(heard.text, "voice")
        spoken = @ambient.speak!(reply)
        { "ok" => true, "heard" => heard.text, "reply" => reply, "spoken" => spoken.ok? }
      end

      private

      def prompt_for(text)
        recent = @session.context_blob
        [@personality.context_snippet, (recent.empty? ? "" : "Recent turns:\n#{recent}"), text]
          .reject(&:empty?).join("\n\n")
      end
    end
  end
end
