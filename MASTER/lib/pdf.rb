# frozen_string_literal: true

require "fileutils"
require "open3"
require "tempfile"

module Master
  # PDF is a derived-output adapter. Markdown remains the canonical source.
  module PDF
    Error = Class.new(StandardError)

    module_function

    def executable = ENV.fetch("MASTER_PDF_ENGINE", "pandoc")

    def available?(command: executable)
      _stdout, _stderr, status = Open3.capture3(command, "--version")
      status.success?
    rescue Errno::ENOENT
      false
    end

    def render(markdown, output:, command: executable, pdf_engine: nil, title: nil)
      raise Error, "#{command} is not available" unless available?(command:)

      output = File.expand_path(output)
      FileUtils.mkdir_p(File.dirname(output))
      Tempfile.create(["master", ".md"]) do |source|
        source.write(Master::MD.normalize(markdown))
        source.flush

        arguments = [source.path, "--from=gfm", "--output=#{output}"]
        arguments << "--pdf-engine=#{pdf_engine}" if pdf_engine
        arguments << "--metadata=title:#{title}" if title && !title.to_s.empty?

        _stdout, stderr, status = Open3.capture3(command, *arguments)
        raise Error, stderr.strip unless status.success?

        output
      end
    end
  end
end
