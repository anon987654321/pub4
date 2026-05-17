module Commentable
  extend ActiveSupport::Concern

  included do
    has_many :comments, as: :commentable, dependent: :destroy
  end

  def root_comments = comments.where(parent_id: nil)
  def comment_count = comments.count
end
