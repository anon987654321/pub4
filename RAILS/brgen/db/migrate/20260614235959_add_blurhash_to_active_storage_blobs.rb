# frozen_string_literal: true

class AddBlurhashToActiveStorageBlobs < ActiveRecord::Migration[8.1]
  def change
    add_column :active_storage_blobs, :blurhash, :string
  end
end
