class Watch < ApplicationRecord
  belongs_to :user
  belongs_to :port

  validates :user_id, uniqueness: { scope: :port_id }
end
