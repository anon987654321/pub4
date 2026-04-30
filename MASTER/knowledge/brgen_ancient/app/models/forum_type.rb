# == Schema Information
#
# Table name: forum_types
#
#  id         :integer          not null, primary key
#  name       :string
#  created_at :datetime
#  updated_at :datetime
#  value      :string
#

class ForumType < ActiveRecord::Base
  has_many :forums, :class_name => "Forem::Forum"
  validates :name, :value, presence: true

  def self.ad
    ForumType.find_by_value("ad")
  end

  def self.regular
    ForumType.find_by_value("regular")
  end

  def self.event
    ForumType.find_by_value("event")
  end
end

