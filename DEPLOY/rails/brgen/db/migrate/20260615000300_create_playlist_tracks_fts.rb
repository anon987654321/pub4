# frozen_string_literal: true

class CreatePlaylistTracksFts < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE VIRTUAL TABLE playlist_tracks_fts USING fts5(
        title, artist, album, genre,
        content='playlist_tracks', content_rowid='id',
        tokenize='unicode61'
      );
      INSERT INTO playlist_tracks_fts(rowid, title, artist, album, genre)
        SELECT id, title, COALESCE(artist, ''), COALESCE(album, ''), COALESCE(genre, '') FROM playlist_tracks;
      CREATE TRIGGER playlist_tracks_ai AFTER INSERT ON playlist_tracks BEGIN
        INSERT INTO playlist_tracks_fts(rowid, title, artist, album, genre)
          VALUES (new.id, new.title, COALESCE(new.artist, ''), COALESCE(new.album, ''), COALESCE(new.genre, ''));
      END;
      CREATE TRIGGER playlist_tracks_au AFTER UPDATE ON playlist_tracks BEGIN
        INSERT INTO playlist_tracks_fts(playlist_tracks_fts, rowid, title, artist, album, genre)
          VALUES ('delete', old.id, old.title, COALESCE(old.artist, ''), COALESCE(old.album, ''), COALESCE(old.genre, ''));
        INSERT INTO playlist_tracks_fts(rowid, title, artist, album, genre)
          VALUES (new.id, new.title, COALESCE(new.artist, ''), COALESCE(new.album, ''), COALESCE(new.genre, ''));
      END;
      CREATE TRIGGER playlist_tracks_ad AFTER DELETE ON playlist_tracks BEGIN
        INSERT INTO playlist_tracks_fts(playlist_tracks_fts, rowid, title, artist, album, genre)
          VALUES ('delete', old.id, old.title, COALESCE(old.artist, ''), COALESCE(old.album, ''), COALESCE(old.genre, ''));
      END;
    SQL
  end

  def down
    execute "DROP TRIGGER IF EXISTS playlist_tracks_ad"
    execute "DROP TRIGGER IF EXISTS playlist_tracks_au"
    execute "DROP TRIGGER IF EXISTS playlist_tracks_ai"
    execute "DROP TABLE IF EXISTS playlist_tracks_fts"
  end
end