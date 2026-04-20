  MiniMime::Configuration.ext_db_path =
    File.join(MIME::Types::Data::PATH, "ext_mime.db")
  MiniMime::Configuration.content_type_db_path =
    File.join(MIME::Types::Data::PATH, "content_type_mime.db")
  