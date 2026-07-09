# frozen_string_literal: true

class CaseMatchReflex < ApplicationReflex
  def find_lawyers
    case_type = element.dataset[:case_type]
    lawyers = Lawyer.where(specialty: case_type).order(rating: :desc).limit(5)

    morph :nothing
    cable_ready.replace(
      selector: "#lawyer-matches",
      html: render(partial: "lawyers/matches", locals: { lawyers: })
    ).broadcast
  end
end