# frozen_string_literal: true

class Tv::ViewEvent < ApplicationRecord
  include Shared::ActivityTrackable
  tracks_activity created: "TvVideoViewed", source_vertical: "tv", visibility: "private", actor: :user

  belongs_to :user
  belongs_to :video, class_name: "Tv::Video", foreign_key: :tv_video_id
end
