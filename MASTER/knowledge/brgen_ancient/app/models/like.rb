# == Schema Information
#
# Table name: likes
#
#  id          :integer          not null, primary key
#  post_id     :integer
#  user_id     :integer
#  created_at  :datetime
#  updated_at  :datetime
#  facebook_id :string
#

class Like < ActiveRecord::Base
  belongs_to :post, :class_name => "Forem::Post", :foreign_key => "post_id"
  belongs_to :user
  after_create { |like| like.post.topic.increment!(:likes_count)  }
  after_destroy { |like| like.post.topic.decrement!(:likes_count)  }
end

