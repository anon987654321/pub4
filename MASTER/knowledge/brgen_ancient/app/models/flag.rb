# == Schema Information
#
# Table name: flags
#
#  id             :integer          not null, primary key
#  user_id        :integer
#  flaggable_id   :integer
#  flaggable_type :string
#  created_at     :datetime
#  updated_at     :datetime
#

class Flag < ActiveRecord::Base
  belongs_to :flaggable, polymorphic: true
end

