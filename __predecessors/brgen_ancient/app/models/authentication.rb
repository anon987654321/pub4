# == Schema Information
#
# Table name: authentications
#
#  id               :integer          not null, primary key
#  user_id          :integer
#  provider         :string
#  uid              :string
#  name             :string
#  oauth_token      :string
#  oauth_expires_at :datetime
#  created_at       :datetime
#  updated_at       :datetime
#

class Authentication < ActiveRecord::Base
  belongs_to :user

  # attr_accessible :oauth_token, :oauth_expires, :provider, :uid, :user_id, :name
end

