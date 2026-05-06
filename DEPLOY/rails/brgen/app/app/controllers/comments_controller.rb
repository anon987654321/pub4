class CommentsController < ApplicationController
  before_action :require_real_user
  before_action :set_commentable

  def create
    @comment = @commentable.comments.build(comment_params)
    @comment.user      = Current.user
    @comment.parent_id = params[:parent_id] if params[:parent_id]

    if @comment.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_back fallback_location: root_path }
      end
    else
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.replace("comment_form", partial: "comments/form", locals: { comment: @comment, commentable: @commentable }) }
        format.html         { redirect_back fallback_location: root_path, alert: @comment.errors.full_messages.to_sentence }
      end
    end
  end

  def destroy
    @comment = Comment.find(params[:id])
    @comment.destroy if @comment.user == Current.user
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.remove(dom_id(@comment)) }
      format.html         { redirect_back fallback_location: root_path }
    end
  end

  private

  def set_commentable
    if params[:post_id]
      @commentable = Post.find(params[:post_id])
    elsif params[:comment_id]
      @commentable = Comment.find(params[:comment_id])
    end
  end

  def comment_params
    params.require(:comment).permit(:content)
  end
end
