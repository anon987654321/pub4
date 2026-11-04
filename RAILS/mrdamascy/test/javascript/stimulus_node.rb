# frozen_string_literal: true

require "open3"

# Runs a Stimulus controller's own source under node with a stand-in
# Controller base class, so its behaviour is exercised without a browser.
# The app's own modules it imports (app/javascript/<name>.js) are inlined.
# The script sees the controller class as `Subject`, assigns the targets
# and values it needs as plain fields, and prints one JSON line to read back.
# Each script is JavaScript source, or the name of a .mjs file beside this
# one; several are joined in order. run_node joins any such parts as given.
module StimulusNode
  def run_stimulus(controller, *scripts)
    run_node(controller_source(controller), *scripts)
  end

  def run_node(*parts)
    skip "node is not installed" unless system("node", "--version", out: File::NULL, err: File::NULL)

    program = parts.map { |part| stimulus_script(part) }.join("\n")
    out, err, status = Open3.capture3("node", "--input-type=module", stdin_data: program)
    assert status.success?, err
    JSON.parse(out.lines.last)
  end

  private

  def controller_source(controller)
    Rails.root.join("app/javascript/controllers/#{controller}_controller.js").read
         .sub(%r{^import \{ Controller \} from "@hotwired/stimulus"\n},
              "class Controller { constructor(element) { this.element = element } }\n")
         .sub("export default class", "const Subject = class")
         .gsub(/^import \{ [\w, ]+ \} from "(\w+)"\n/) { app_module(Regexp.last_match(1)) }
  end

  def app_module(name)
    Rails.root.join("app/javascript/#{name}.js").read.gsub(/^export /, "")
  end

  def stimulus_script(part)
    part.end_with?(".mjs") ? File.read(File.join(__dir__, part)) : part
  end
end
