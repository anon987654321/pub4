# frozen_string_literal: true

class ExpiredMessagesSweepJob < ApplicationJob
  queue_as :bulk

  def perform
    Message.where(expires_at: ..Time.current).find_each(&:destroy)
  end
end