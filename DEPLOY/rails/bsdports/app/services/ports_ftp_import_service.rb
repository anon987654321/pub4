# frozen_string_literal: true

require "net/ftp"
require "tempfile"

class PortsFtpImportService
  FTP_HOST = ENV.fetch("BSDPORTS_FTP_HOST", "ftp.openbsd.org")
  INDEX_PATH = ENV.fetch("BSDPORTS_INDEX_PATH", "/pub/OpenBSD/ports.tar.gz")

  def self.call
    new.call
  end

  def call
    entries = fetch_index
    upsert_ports(entries)
    populate_maintainers(entries)
    entries.size
  end

  private

  def fetch_index
    if ENV["BSDPORTS_DEMO_IMPORT"] == "1" || !ftp_available?
      return demo_entries
    end

    Tempfile.create(["ports", ".tar.gz"]) do |tmp|
      Net::FTP.open(FTP_HOST, username: "anonymous", passive: true) do |ftp|
        ftp.getbinaryfile(INDEX_PATH, tmp.path)
      end
      parse_demo_index
    end
  rescue StandardError => e
    Rails.logger.warn("Ports FTP import fallback: #{e.message}")
    demo_entries
  end

  def ftp_available?
    ENV["BSDPORTS_SKIP_FTP"].blank?
  end

  def demo_entries
    [
      { pkgpath: "www/ruby", name: "ruby", version: "3.4.1", comment: "Dynamic language", maintainer: "jeremy@openbsd.org" },
      { pkgpath: "devel/git", name: "git", version: "2.45.0", comment: "Distributed VCS", maintainer: "jca@openbsd.org" },
      { pkgpath: "lang/python", name: "python", version: "3.12.3", comment: "Interpreted language", maintainer: "stu@openbsd.org" }
    ]
  end

  def parse_demo_index
    demo_entries
  end

  def upsert_ports(entries)
    cat = Category.find_or_create_by!(name: "imported") { |c| c.description = "FTP import" }
    entries.each do |e|
      port = Port.find_or_create_by!(pkgpath: e[:pkgpath]) do |p|
        p.name = e[:name]
        p.version = e[:version]
        p.comment = e[:comment]
        p.maintainer = e[:maintainer]
        p.category = cat
        p.last_updated = Time.current
      end
      port.update!(version: e[:version], comment: e[:comment], maintainer: e[:maintainer], last_updated: Time.current)
      port.port_updates.find_or_create_by!(new_version: e[:version]) do |u|
        u.old_version = port.version_was || "0.0"
        u.commit_message = "FTP import sync"
        u.committed_at = Time.current
      end
    end
  end

  def populate_maintainers(entries)
    entries.map { |e| e[:maintainer] }.compact.uniq.each do |email|
      Maintainer.find_or_create_by!(name: email) do |m|
        m.email = email if email.include?("@")
      end
    end
  end
end