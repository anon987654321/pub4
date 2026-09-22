# frozen_string_literal: true

# PostproJob adds a graded photo alongside the originals (replace: false) --
# it does not swap them -- and until now nothing on the listing said whether
# that had happened yet. nil means no postpro was ever requested for this
# listing; the four states below only apply once the create action enqueues
# the job.
class AddPhotoStatusToMarketplaceListings < ActiveRecord::Migration[8.1]
  def change
    add_column :marketplace_listings, :photo_status, :string
  end
end
