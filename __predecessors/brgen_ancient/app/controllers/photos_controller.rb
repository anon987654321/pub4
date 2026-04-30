class PhotosController < ApplicationController
  def new
    render "new", layout: false
  end

  # -------------------------------------------------

  def photo_params
    params.require(:photo).permit(:post_id, :attachment, :processed_attachment, :filter_data)
  end

  # -------------------------------------------------

  def check_photo_processing

    # Delayed Paperclip handles `attachment_processing` automatically

    # Corresponds to `photos` table in the database

    @photo_status = Photo.find(params[:id]).attachment_processing

    respond_to :js
  end
end

