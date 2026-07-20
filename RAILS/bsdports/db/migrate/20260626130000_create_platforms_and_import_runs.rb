# frozen_string_literal: true

class CreatePlatformsAndImportRuns < ActiveRecord::Migration[8.1]
  PLATFORMS = [
    { name: "OpenBSD", slug: "openbsd", tree_path: "/usr/ports", mirror_url: "ftp://ftp.openbsd.org/pub/OpenBSD" },
    { name: "FreeBSD", slug: "freebsd", tree_path: "/usr/ports", mirror_url: "ftp://ftp.freebsd.org/pub/FreeBSD" },
    { name: "NetBSD", slug: "netbsd", tree_path: "/usr/pkgsrc", mirror_url: "ftp://ftp.netbsd.org/pub/pkgsrc" },
  ].freeze

  def up
    create_table :platforms do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.string :tree_path
      t.string :mirror_url
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :platforms, :slug, unique: true

    create_table :import_runs do |t|
      t.references :platform, null: false, foreign_key: true
      t.string :status, null: false, default: "running"
      t.datetime :started_at, null: false
      t.datetime :finished_at
      t.integer :ports_count, null: false, default: 0
      t.string :source_revision
      t.text :error_message
      t.timestamps
    end
    add_index :import_runs, %i[platform_id started_at]

    PLATFORMS.each do |attrs|
      execute <<~SQL.squish
        INSERT INTO platforms (name, slug, tree_path, mirror_url, active, created_at, updated_at)
        VALUES (#{quote(attrs[:name])}, #{quote(attrs[:slug])}, #{quote(attrs[:tree_path])},
                #{quote(attrs[:mirror_url])}, 1, #{quote(Time.current)}, #{quote(Time.current)})
      SQL
    end

    openbsd_id = select_value("SELECT id FROM platforms WHERE slug = 'openbsd'")

    add_reference :categories, :platform, foreign_key: true
    add_reference :ports, :platform, foreign_key: true

    execute "UPDATE categories SET platform_id = #{openbsd_id}"
    execute "UPDATE ports SET platform_id = #{openbsd_id}"

    change_column_null :categories, :platform_id, false
    change_column_null :ports, :platform_id, false

    remove_index :ports, :name
    add_index :ports, :name
    remove_index :ports, :pkgpath
    add_index :ports, %i[platform_id pkgpath], unique: true
    remove_index :categories, :slug
    add_index :categories, %i[platform_id slug], unique: true
  end

  def down
    remove_index :categories, column: %i[platform_id slug]
    add_index :categories, :slug, unique: true
    remove_index :ports, column: %i[platform_id pkgpath]
    add_index :ports, :pkgpath, unique: true
    remove_index :ports, :name
    add_index :ports, :name, unique: true

    remove_reference :ports, :platform, foreign_key: true
    remove_reference :categories, :platform, foreign_key: true
    drop_table :import_runs
    drop_table :platforms
  end
end
