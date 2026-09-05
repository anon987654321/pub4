# frozen_string_literal: true

# A polymorphic join: this post named that user. Shared::Mentionable writes
# the row from @username in title and content.
class Mention < ApplicationRecord
  belongs_to :mentionable, polymorphic: true, inverse_of: :mentions
  belongs_to :mentioned_user, class_name: "User"

  def self.extract(text)
    text.to_s.scan(/(?<![a-zA-Z0-9_])@([a-zA-Z0-9_]+)/).flatten.uniq
  end
end

