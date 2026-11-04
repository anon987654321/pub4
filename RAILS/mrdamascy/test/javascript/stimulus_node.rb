# frozen_string_literal: true

require "open3"

# Runs a Stimulus controller's own source under node with a stand-in
# Controller base class, so its behaviour is exercised without a browser.
# The script sees the controller class as `Subject`, assigns the targets
# and values it needs as plain fields, and prints one JSON line to read back.
module StimulusNode
  def run_stimulus(controller, script)
    skip "node is not installed" unless system("node", "--version", out: File::NULL, err: File::NULL)

    source = Rails.root.join("app/javascript/controllers/#{controller}_controller.js").read
    source = source.sub(%r{^import \{ Controller \} from "@hotwired/stimulus"\n},
                        "class Controller { constructor(element) { this.element = element } }\n")
                   .sub("export default class", "const Subject = class")
    out, err, status = Open3.capture3("node", "--input-type=module", stdin_data: "#{source}\n#{script}")
    assert status.success?, err
    JSON.parse(out.lines.last)
  end
end
