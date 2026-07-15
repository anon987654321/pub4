# frozen_string_literal: true

class Comment < ApplicationRecord
  include Shared::CommentThreading

  belongs_to :user
  belongs_to :commentable, polymorphic: true, touch: true

  validates :content, presence: true, length: { maximum: 2000 }
end
