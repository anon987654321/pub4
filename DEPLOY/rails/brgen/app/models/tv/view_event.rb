class Tv::ViewEvent < ApplicationRecord
  belongs_to :user
  belongs_to :video, class_name: "Tv::Video", foreign_key: :tv_video_id
end
