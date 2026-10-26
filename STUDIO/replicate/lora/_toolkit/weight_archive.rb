# frozen_string_literal: true

require "fileutils"
require "pathname"
require "rubygems/package"
require "tmpdir"
require_relative "preflight"

module Lora
  # Extract only regular checkpoint bytes from provider archives. Never delegate
  # extraction of untrusted links, permissions or paths to the system tar tool.
  module WeightArchive
    module_function

    def extract(tar_path, dest_dir)
      unsafe = Preflight.unsafe_tar_entries(tar_path.to_s)
      raise ArgumentError, "refusing #{tar_path}: #{unsafe.first(3).join(', ')}" unless unsafe.empty?

      destination = Pathname.new(dest_dir).expand_path
      FileUtils.mkdir_p(destination)
      published = []

      # Stage beside the destination to keep final hard-link publication on one
      # filesystem. Staging is private and removed automatically on every exit.
      Dir.mktmpdir(".weights-stage-", destination.to_s) do |staging|
        staged = []
        File.open(tar_path, "rb") do |file|
          Gem::Package::TarReader.new(file).each do |entry|
            next unless ["0", "\0"].include?(entry.header.typeflag.to_s)

            name = entry.full_name.to_s
            next unless name.downcase.end_with?(".safetensors")

            basename = File.basename(name)
            # A tar made on macOS carries ._model.safetensors, the AppleDouble record of
            # model.safetensors's extended attributes. It is not a checkpoint.
            next if basename.start_with?("._")

            staged_path = File.join(staging, basename)
            raise ArgumentError, "duplicate weight basename #{basename.inspect}" if File.exist?(staged_path)

            File.open(staged_path, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |output|
              IO.copy_stream(entry, output)
              output.flush
              output.fsync
            end
            raise ArgumentError, "empty checkpoint #{name.inspect}" unless File.size(staged_path).positive?

            staged << staged_path
          end
        end

        raise ArgumentError, "trainer archive contained no nonempty .safetensors weights" if staged.empty?

        begin
          staged.each do |source|
            filename = File.basename(source)
            target = destination.join(filename)
            suffix = 1
            while target.exist? || target.symlink?
              stem = File.basename(filename, ".safetensors")
              target = destination.join("#{stem}-restored-#{suffix}.safetensors")
              suffix += 1
            end
            File.link(source, target.to_s)
            published << target.to_s
          end
          fsync_directory(destination.to_s) if RUBY_PLATFORM !~ /win32|mingw/
        rescue StandardError
          published.each do |path|
            File.unlink(path) if File.file?(path) && !File.symlink?(path)
          end
          raise
        end
      end

      published
    end

    def fsync_directory(directory)
      descriptor = IO.sysopen(directory, File::RDONLY)
      dir_io = IO.new(descriptor)
      dir_io.fsync
    ensure
      dir_io&.close
    end
    private_class_method :fsync_directory
  end
end
