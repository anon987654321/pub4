# frozen_string_literal: true

class MasterChannel < ApplicationCable::Channel
  def subscribed
    stream_from "master:events"
    stream_from "master:council"
    stream_from "master:status"
  end
end