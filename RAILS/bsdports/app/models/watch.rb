# frozen_string_literal: true

class Watch < ApplicationRecord
  # Engine-ize Shared
  include Shared::Notifiable
  include Shared::Reactable
  belongs_to :user
  belongs_to :port

  validates :user_id, uniqueness: { scope: :port_id }
end
