# frozen_string_literal: true

class PortsImportJob < ApplicationJob
  queue_as :default

  def perform(index_file_path)
    File.foreach(index_file_path) do |line|
      next if line.blank? || line.start_with?("#")
      pkgname, dir, maintainer_email, run_deps = line.chomp.split("|")
      maintainer = Maintainer.find_or_create_by!(email: maintainer_email)
      port = Port.find_or_initialize_by(pkgname: pkgname)
      port.update!(directory: dir, maintainer: maintainer)
      next if run_deps.blank?
      run_deps.split(",").each do |dep_pkg|
        dep_port = Port.find_by(pkgname: dep_pkg.strip)
        Dependency.find_or_create_by!(port: port, depends_on: dep_port, dep_type: "run") if dep_port
      end
    end
  end
end
