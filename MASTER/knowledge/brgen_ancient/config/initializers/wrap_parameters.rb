
# Enable parameter wrapping for JSON

ActiveSupport.on_load(:action_controller) do
  wrap_parameters :format => [:json]
end

# Disable root element in JSON

ActiveSupport.on_load(:active_record) do
  self.include_root_in_json = false
end

