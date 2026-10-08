# frozen_string_literal: true

# Promoted to shared to reduce duplication and centralize (part of engine prep + sprawl reduction).
module Shared
  module Commentable
    extend ActiveSupport::Concern

    included do
      has_many :comments, as: :commentable, dependent: :destroy, strict_loading: false, inverse_of: :commentable
    end

    def root_comments = comments.where(parent_id: nil)
    def comment_count = comments.count
  end
end
