# frozen_string_literal: true

class ArticleView < ApplicationRecord
  belongs_to :post

  validates :viewer_token, presence: true, uniqueness: { scope: :post_id }
end