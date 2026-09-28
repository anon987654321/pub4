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

    def reply(messages:, sender:, message:, session_key:, channel:)
      result = @client.turn(
        prompt(messages:, sender:, message:),
        session_key:,
        channel:,
      )
      return unless result["ok"]

      output = result["output"].to_s.strip
      output unless output.empty?
    rescue StandardError
      nil
    end

    private

    def prompt(messages:, sender:, message:)
      <<~TEXT.byteslice(0, MAX_PROMPT_BYTES)
        You are MASTER, the shared assistant invited into a messenger conversation.
        You are a participant, not the owner of the conversation. Answer the latest human
        message directly, preserve participant privacy, and never invent access to data or actions.
        Re-read or research when the question needs current evidence.

        Conversation:
        #{transcript(messages)}

        Latest sender: #{sender_name(sender)}
        Latest message:
        #{message_text(message)}
      TEXT
    end

    def transcript(messages)
      Array(messages).last(MAX_CONTEXT).map { |row| "#{sender_name(row.sender)}: #{message_text(row)}" }.join("\n")
    end

    def message_text(message)
      message.respond_to?(:body) ? message.body.to_s : message.content.to_s
    end

    def sender_name(sender)
      sender.respond_to?(:channel_handle) ? sender.channel_handle : sender.display_name
    end
  end
end
