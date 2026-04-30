module PhotoUtils
  def self.store_data(params, post)

    # Delete all photos as we'll be recreating them below

    post.photos.destroy_all

    if !params[:original_photos]
      return
    end

    params[:original_photos].each_with_index do |original_photo, i|
      photo = Photo.new
      photo.post_id = post.id

      # TODO: `name = params[:photo_names][i]`

      photo.attachment = original_photo

      # Processed photo, pass even if unchanged

      photo.processed_attachment = params[:processed_photos][i]

      # Finish up

      photo.filter_data = params[:filter_data][i]
      photo.save
    end
  end
end

