class FlagsController < Forem::ApplicationController
  def create
    @post = Forem::Post.find(params[:post_id])
    @flag = @post.flags.build(user_id: forem_user.id)
    @flag.save
    render :toggle, post: @post
  end

  def destroy
    flag = Flag.find(params[:id]).destroy
    @post = flag.flaggable
    render :toggle, post: @post
  end
end

