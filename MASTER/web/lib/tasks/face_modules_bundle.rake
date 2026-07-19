# frozen_string_literal: true

namespace :assets do
  desc "Build public/face.modules.bundle.js (single request for face module boot)"
  task build_face_modules_bundle: :environment do
    script = Rails.root.join("script/build_face_modules.sh")
    raise "missing #{script}" unless File.file?(script)

    system(script.to_s, exception: true)
    out = Rails.root.join("public/face.modules.bundle.js")
    raise "build_face_modules.sh did not write #{out}" unless File.file?(out)

    puts "wrote #{out} (#{File.size(out)} bytes)"
  end
end

if Rake::Task.task_defined?("assets:precompile")
  Rake::Task["assets:precompile"].enhance(["assets:build_face_modules_bundle"])
end
