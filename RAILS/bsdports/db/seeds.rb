# frozen_string_literal: true

# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
Platform.find_or_create_by!(slug: "openbsd") do |platform|
  platform.name = "OpenBSD"
  platform.tree_path = "/usr/ports"
  platform.mirror_url = "ftp://ftp.openbsd.org/pub/OpenBSD"
end

Platform.find_or_create_by!(slug: "freebsd") do |platform|
  platform.name = "FreeBSD"
  platform.tree_path = "/usr/ports"
  platform.mirror_url = "ftp://ftp.freebsd.org/pub/FreeBSD"
  platform.active = false
end

Platform.find_or_create_by!(slug: "netbsd") do |platform|
  platform.name = "NetBSD"
  platform.tree_path = "/usr/pkgsrc"
  platform.mirror_url = "ftp://ftp.netbsd.org/pub/pkgsrc"
  platform.active = false
end
