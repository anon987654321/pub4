# frozen_string_literal: true

# A video had no audio identity, so there was nothing to browse more of, and no
# way to make a video that answers another one.
class CreateTvSoundsAndDuets < ActiveRecord::Migration[8.1]
  def change
    create_table :tv_sounds do |t|
      # Whose audio it was first. The video it came from can be deleted and the
      # sound outlives it, the way it does everywhere this exists: the clips
      # that used it are the reason it is still a thing.
      t.references :user, null: false, foreign_key: true
      t.references :source_video, null: true, foreign_key: { to_table: :tv_videos }
      t.string :title, null: false
      t.integer :videos_count, null: false, default: 0
      t.timestamps
    end

    add_reference :tv_videos, :sound, null: true, foreign_key: { to_table: :tv_sounds }
    # A duet names the video it answers. Self-referential and nullable, because
    # most videos answer nothing.
    add_reference :tv_videos, :duet_of, null: true, foreign_key: { to_table: :tv_videos }
    # Whether this video may be answered. Default true, because a video posted
    # to a public feed is already public — but a creator who does not want their
    # face beside a stranger's has to be able to say so.
    add_column :tv_videos, :allow_duets, :boolean, null: false, default: true
  end
end
