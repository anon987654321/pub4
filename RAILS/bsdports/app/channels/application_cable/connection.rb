# frozen_string_literal: true

module ApplicationCable
  class Connection < ActionCable::Connection::Base
    include Shared::CableIdentity
  end
end
