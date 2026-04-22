# frozen_string_literal: true

# Configure MiniMime to use the bundled MIME‑type data files.
#
# The data files are part of the `mime-types-data` gem and live under
# `MIME::Types::Data::PATH`.  `File.expand_path` together with `File.join`
# yields an absolute, platform‑neutral path, which is essential on
# OpenBSD where path handling is strict.

ext_path = ::File.expand_path(
  ::File.join(MIME::Types::Data::PATH, "ext_mime.db")
)

content_type_path = ::File.expand_path(
  ::File.join(MIME::Types::Data::PATH, "content_type_mime.db")
)

MiniMime::Configuration.ext_db_path = ext_path
MiniMime::Configuration.content_type_db_path = content_type_path