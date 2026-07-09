# frozen_string_literal: true

class Stream < ApplicationRecord
  belongs_to :user
  belongs_to :post
end
