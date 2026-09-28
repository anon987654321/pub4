# frozen_string_literal: true

module Shared
  # One messenger adapter for every mounted app. It talks to the authenticated
  # MASTER bridge, so brgen and Amber invite the same runtime rather than
  # maintaining separate assistant personalities or memory.
  class MasterMessenger
    MAX_CONTEXT = 24
    MAX_PROMPT_BYTES = 12_000

    def initialize(client: MasterClient.new)
      @client = client
    end

    def available? = @client.available?

    def reply(conversation:, sender:, message:)
      result = @client.turn(
        prompt(conversation:, sender:, message:),
        session_key: "messenger:#{conversation_key(conversation)}",
        channel: "messenger",
      )
      return unless result["ok"]

      result["output"].to_s.strip.presence
    rescue StandardError
      nil
    end

    private

    def prompt(conversation:, sender:, message:)
      <<~TEXT.byteslice(0, MAX_PROMPT_BYTES)
        You are MASTER, the shared assistant invited into a private messenger conversation.
        You are a participant, not the owner of the conversation. Answer the latest human
        message directly, preserve privacy, and never invent access to data or actions.
        Re-read or research when the question needs current evidence.

        Conversation:
        #{transcript(conversation)}

        Latest sender: #{sender_name(sender)}
        Latest message:
        #{message.body_or_content}
      TEXT
    end

    def transcript(conversation)
      rows = conversation.messages.includes(:sender).order(created_at: :desc).limit(MAX_CONTEXT).reverse
      rows.map { |message| "#{sender_name(message.sender)}: #{message.body_or_content}" }.join("\n")
    end

    def conversation_key(conversation)
      app = conversation.class.name.underscore.tr("/", "_")
      "#{app}:#{conversation.id}"
    end

    def sender_name(sender)
      sender.respond_to?(:channel_handle) ? sender.channel_handle : sender.display_name
    end
  end
end
