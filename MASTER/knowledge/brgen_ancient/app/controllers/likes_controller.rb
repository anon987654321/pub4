class LikesController < Forem::ApplicationController
  def create
    @like = Like.create({ post_id: params[:post_id], user_id: forem_user.id })
    @post = @like.post

    # Send to background with Delayed::Job and load via Ajax later on

    Brgen::Facebook.delay.post(forem_user.id, @like.id, "Like", "like", forem.forum_topic_url(@post.topic.forum, @post.topic)) if forem_user.facebook_user?

    render :toggle, post: @post
  end

  def destroy
    like = Like.find(params[:id]).destroy
    @post = like.post

    Brgen::Facebook.delay.delete(forem_user.id, like.facebook_id) if forem_user.facebook_user?

    render :toggle, post: @post
  end

protected
  def like_params
    params.require(:like).permit(:post_id, :user_id, :facebook_id)
  end
end

