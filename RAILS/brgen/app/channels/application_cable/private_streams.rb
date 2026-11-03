# frozen_string_literal: true

module ApplicationCable
  # Who may read a stream that belongs to somebody, asked again at every
  # subscribe. A signed stream name never expires: the page that held it, a
  # copied tab or a removed group member's open window can present it a year
  # later, and the signature still verifies. So the name proves only that this
  # app once rendered it; membership is checked now.
  #
  # A private conversation (a DM or a group DM: no slug) streams to its current
  # participants only. A public channel is open to the city like its page is.
  # A person's inbox and notifications stream to that person only.
  module PrivateStreams
    PERSONAL = [ [ "inbox" ], [ "notifications" ] ].freeze

    def self.allowed?(stream_name, user)
      head, *rest = stream_name.to_s.split(":")
      gid = GlobalID.parse(head)
      case gid&.model_name
      when "Conversation" then rest.empty? ? conversation_member?(gid.model_id, user) : true
      when "User" then PERSONAL.include?(rest) ? gid.model_id == user.id.to_s : true
      else true
      end
    rescue URI::Error, ArgumentError
      true
    end

    def self.conversation_member?(conversation_id, user)
      conversation = Conversation.find_by(id: conversation_id)
      return true if conversation.nil? || conversation.slug.present?

      ConversationParticipant.exists?(conversation_id: conversation.id, user_id: user.id)
    end
  end
end
