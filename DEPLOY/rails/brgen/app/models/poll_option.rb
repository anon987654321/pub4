# frozen_string_literal: true

class PollOption < ApplicationRecord
  belongs_to :poll, counter_cache: :options_count
  has_many :poll_votes, dependent: :destroy

  def votes_count
    poll_votes.count
  end
end