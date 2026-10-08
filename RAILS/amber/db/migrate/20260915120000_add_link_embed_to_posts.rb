# frozen_string_literal: true

# The media player a post's link resolves to, as Shared::LinkEmbeddable stores
# it: provider, link, id, title, author, thumbnail and when it was asked. One
# JSON column rather than a table, because a post embeds at most one link and a
# column needs no association for a strict-loading feed to preload.
class AddLinkEmbedToPosts < ActiveRecord::Migration[8.1]
  def change
    add_column :posts, :link_embed, :json
  end
end
