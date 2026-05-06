class Tagging < ApplicationRecord
  belongs_to :taggable, polymorphic: true
  belongs_to :hashtag
end
