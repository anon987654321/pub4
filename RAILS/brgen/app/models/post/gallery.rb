# frozen_string_literal: true

class Post
  # A post's photo gallery as its author arranges it on the edit form: photos
  # added, taken off and put in order. New posts already took images[]; the edit
  # form offered only the single image field, so a gallery could not be changed
  # once posted.
  #
  # The order is image_order, the attachment ids as the author set them. Any
  # image the list does not name (one added since) follows in upload order.
  module Gallery
    def ordered_images
      order = Array(image_order).map(&:to_i)
      images.sort_by { |image| [ order.index(image.id) || order.size, image.id ] }
    end

    # add: uploaded files or signed blob ids; remove_ids: attachment ids to take
    # off; positions: { attachment_id => number } from the form. Only this post's
    # own attachments are touched, whatever ids the form sends.
    def arrange_gallery(add: [], remove_ids: [], positions: {})
      uploads = Array(add).compact_blank
      images.attach(uploads) if uploads.any?
      own = images_attachments.reload.index_by(&:id)
      Array(remove_ids).map(&:to_i).filter_map { own.delete(_1) }.each(&:purge_later)

      # updated_at too: the feed card is cached on the post, and a new order
      # has to reach it.
      update_columns(image_order: gallery_order(own.keys, positions), updated_at: Time.current)
    end

    private

    def gallery_order(ids, positions)
      wanted = positions.to_h.transform_keys(&:to_i).transform_values { Integer(_1, exception: false) }
      current = Array(image_order).map(&:to_i)
      ids.sort_by { |id| [ wanted[id] || Float::INFINITY, current.index(id) || ids.size, id ] }
    end
  end
end
