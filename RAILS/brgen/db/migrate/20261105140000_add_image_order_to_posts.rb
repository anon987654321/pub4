# frozen_string_literal: true

# The order of a post's gallery, as the attachment ids in the order the author
# set on the edit form. Nil until the author reorders; Post#ordered_images falls
# back to upload order for any image the list does not name.
class AddImageOrderToPosts < ActiveRecord::Migration[8.1]
  def change
    add_column :posts, :image_order, :json
  end
end
