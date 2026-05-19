# frozen_string_literal: true

class Tagging < ApplicationRecord
  belongs_to :taggable, polymorphic: true
  belongs_to :hashtag
end
