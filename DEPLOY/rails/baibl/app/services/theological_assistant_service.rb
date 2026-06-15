# frozen_string_literal: true

class TheologicalAssistantService
  def self.answer(question:, verse: nil, user: nil)
    context = verse ? "#{verse.reference}: #{verse.content}" : ""
    refs = verse&.cross_references&.includes(target_verse: %i[book chapter])&.limit(3)&.map { |xr| xr.target_verse.reference } || []

    {
      question: question,
      summary: "Thoughtful reflection on #{question.truncate(80)}",
      context: context,
      cross_references: refs,
      guidance: [
        "Consider the historical and literary context of the passage.",
        "Compare related cross-references before drawing application.",
        "Discuss insights with your community or study group."
      ],
      disclaimer: "AI assistant — not a substitute for pastoral counsel or scholarly exegesis."
    }
  end
end