SimpleForm.setup do |config|
  config.wrappers :default, class: :input, hint_class: :field_with_hint, error_class: :field_with_errors do |b|

    # DEFAULT

    # Determines whether to use HTML5 (`:email`, `:url` etc.) and required attributes

    b.use :html5

    # Calculates placeholders from I18n

    b.use :placeholder

    # -------------------------------------------------

    # OPTIONAL

    # Calculates maxlength from length validations for string inputs

    b.optional :maxlength

    # Calculates pattern from format validations for string inputs

    b.optional :pattern

    # Calculates min and max from length validations for numeric inputs

    b.optional :min_max

    # Calculates read-only automatically from readonly attributes

    b.optional :readonly

    # -------------------------------------------------

    # Inputs

    b.use :label_input
    b.use :hint,  wrap_with: { tag: :span, class: :hint }
    b.use :error, wrap_with: { tag: :span, class: :error }
  end

  # Default wrapper to be used by FormBuilder

  config.default_wrapper = :default

  # Define how to render check boxes / radio buttons with labels

  config.boolean_style = :nested

  # Default class for buttons

  config.button_class = "button"

  # Default tag used for error notification helper

  config.error_notification_tag = :div

  # CSS class to add for error notification helper

  config.error_notification_class = "error_notification"

  # Define the default class of the input wrapper of the boolean input

  config.boolean_label_class = "checkbox"

  # Tell browsers whether to use native HTML5 form validations (`novalidate`)

  config.browser_validations = false

  # -------------------------------------------------

  # Do not add action / model classes to forms, ie. `new_topic`, `new_post` etc.

  # http://goo.gl/fI3iwy

  config.default_form_class = nil

  # How the label text should be generated altogether with the required text

  # Remove asterisk

  # http://goo.gl/qYsVRM

  config.label_text = lambda { |label, required, explicit_label| "#{label}" }
end

