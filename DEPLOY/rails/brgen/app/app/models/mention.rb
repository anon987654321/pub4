class Mention < ApplicationRecord
  belongs_to :mentionable, polymorphic: true
  belongs_to :mentioned_user
end
