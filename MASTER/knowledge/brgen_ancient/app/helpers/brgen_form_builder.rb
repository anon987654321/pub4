class BrgenFormBuilder < SimpleForm::FormBuilder
  def photo_field(method, options={})
    file = file_field method, :class => "attachment_file"
    photo_editor(file, options[:data])
  end

  def input(attribute_name, options = {}, &block)

    # Assign random IDs to inputs

    if options[:input_html]
      options[:input_html].merge! id: random_id
    else
      options[:input_html] = { id: random_id }
    end
    super
  end

private
  def random_id
    Brgen::UtilityMethods.random_id
  end
end

