# encoding: utf-8
# Enhanced user interaction module

class UserInteraction
  def initialize(interface)
    @interface = interface
  end

  def get_input
    @interface.receive_input
  end

  def provide_feedback(response)
    @interface.display_output(response)
  end

  def get_feedback
    @interface.receive_feedback
  end
end
