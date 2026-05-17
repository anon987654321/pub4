class HomeController < ApplicationController
  def index
    @posts = if authenticated?
               Current.user.timeline_posts.hot.includes(:user, :community, :votes).limit(50)
             else
               Post.hot.includes(:user, :community, :votes).limit(50)
             end
    @communities = Community.popular.limit(10)
  end
end
