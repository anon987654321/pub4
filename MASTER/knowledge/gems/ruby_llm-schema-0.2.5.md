class PersonSchema < RubyLLM::Schema
  # -----------------------------------------------------------------
  # Core attributes
  # -----------------------------------------------------------------
  string :name,
    description: "Full name of the person",
    required:   true

  number :age,
    description: "Age in years",
    minimum:    0,
    maximum:    120,
    required:   true

  boolean :active,
    description: "Whether the person is currently active",
    required:    false,
    default:     true

  # -----------------------------------------------------------------
  # Nested address object
  # -----------------------------------------------------------------
  object :address,
    description: "Physical mailing address",
    required:    false do
      string :street,
        description: "Street name and number",
        required:    true

      string :city,
        description: "City of residence",
        required:    true

      string :country,
        description: "ISO 3166‑1 alpha‑2 country code",
        pattern:     "^[A-Z]{2}$",
        required:    true
    end

  # -----------------------------------------------------------------
  # Simple collections
  # -----------------------------------------------------------------
  array :tags,
    description: "Arbitrary tags describing the person",
    of:          :string,
    uniqueItems: true,
    minItems:    0

  # -----------------------------------------------------------------
  # Complex collection of contact objects
  # -----------------------------------------------------------------
  array :contacts,
    description: "Contact methods for the person",
    of:          :object,
    required:    false do
      string :email,
        description: "Primary email address",
        format:      :email,
        required:    true

      string :phone,
        description: "Phone number in E.164 format",
        pattern:     "^\\+?[1-9]\\d{1,14}$",
        required:    false
    end

  # -----------------------------------------------------------------
  # Polymorphic status field
  # -----------------------------------------------------------------
  any_of :status,
    description: "Current lifecycle status",
    enum:        %w[active pending inactive],
    nullable:    true,
    default:     "pending"
end