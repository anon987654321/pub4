class PersonSchema < RubyLLM::Schema
  # frozen_string_literal: true

  # ----------------------------------------------------------------------
  # Core fields
  # ----------------------------------------------------------------------
  string :name,
    description: "Full name",
    required: true

  number :age,
    description: "Age in years",
    minimum: 0,
    maximum: 120,
    required: true

  boolean :active,
    description: "Account enabled",
    default: true,
    required: false

  # ----------------------------------------------------------------------
  # Nested address object – street and city are mandatory; country optional.
  # ----------------------------------------------------------------------
  object :address do
    string :street,
      description: "Street address",
      required: true

    string :city,
      description: "City name",
      required: true

    string :country,
      description: "ISO‑3166‑1 alpha‑2 country code",
      pattern: "^[A-Z]{2}$",
      required: false
  end

  # ----------------------------------------------------------------------
  # Arbitrary tags – useful for classification or filtering.
  # ----------------------------------------------------------------------
  array :tags,
    description: "Free‑form tags",
    of: :string,
    uniqueItems: true,
    minItems: 0

  # ----------------------------------------------------------------------
  # Contact information – each entry must contain an email; phone optional.
  # ----------------------------------------------------------------------
  array :contacts,
    description: "Contact methods",
    minItems: 0 do
    object do
      string :email,
        description: "Valid email address",
        format: "email",
        required: true

      string :phone,
        description: "E.164 phone number",
        pattern: "^\\+?[1-9]\\d{1,14}$",
        required: false
    end
  end

  # ----------------------------------------------------------------------
  # Status – enumerated values with explicit null support.
  # ----------------------------------------------------------------------
  any_of :status,
    enum: %w[active pending inactive],
    nullable: true,
    description: "Current lifecycle state"

  # ----------------------------------------------------------------------
  # Serialization helper – pretty‑printed JSON.
  # ----------------------------------------------------------------------
  def to_json(*)
    JSON.pretty_generate(to_h)
  end
end
