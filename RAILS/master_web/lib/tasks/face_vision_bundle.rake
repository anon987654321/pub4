# frozen_string_literal: true

namespace :assets do
  desc "Build public/face_vision.bundle.js (single request for vision layer)"
  task build_face_vision_bundle: :environment do
    script = Rails.root.join("script/build_face_vision.sh")
    raise "missing #{script}" unless File.file?(script)

    system(script.to_s, exception: true)
    out = Rails.root.join("public/face_vision.bundle.js")
    raise "build_face_vision.sh did not write #{out}" unless File.file?(out)
  end
end

if Rake::Task.task_defined?("assets:precompile")
  Rake::Task["assets:precompile"].enhance(["assets:build_face_vision_bundle"])
end
