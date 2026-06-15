# frozen_string_literal: true

class Poll < ApplicationRecord
  belongs_to :post
  has_many :poll_options, dependent: :destroy
  has_many :poll_votes, through: :poll_options

  validates :closes_at, presence: true
  scope :open, -> { where("closes_at > ?", Time.current) }

  after_create_commit -> { broadcast_replace_to post, target: dom_id(post, :poll), partial: "polls/poll", locals: { poll: self } }
end