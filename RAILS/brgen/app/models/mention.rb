# frozen_string_literal: true

class Mention < ApplicationRecord
  belongs_to :mentionable, polymorphic: true
  belongs_to :mentioned_user, class_name: "User"
end
