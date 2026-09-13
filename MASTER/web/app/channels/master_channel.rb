# frozen_string_literal: true

# One stream: cable_bridge.rb broadcasts every bus event on master:events and
# nothing else.
class MasterChannel < ApplicationCable::Channel
  def subscribed
    stream_from "master:events"
  end
end
