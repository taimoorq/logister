# frozen_string_literal: true

# A guided task done on the project's own data, as opposed to a setup path, which
# gets the project working. A walkthrough keeps no state of its own: where you
# are is in the URL, and what you did is the issue's own state.
class Walkthrough
  Step = Data.define(:key, :title, :summary)

  attr_reader :key, :title, :summary, :section_key, :needs, :steps

  def initialize(key:, title:, summary:, section_key:, needs:, steps:)
    @key = key
    @title = title
    @summary = summary
    @section_key = section_key
    @needs = needs
    @steps = steps.freeze
    freeze
  end

  TRIAGE = new(
    key: :triage,
    title: "Triage your first issue",
    summary: "Read an issue, check what shipped, give it an owner, and close the loop. It uses one of this project's real issues.",
    section_key: :issues,
    needs: "an open issue",
    steps: [
      Step.new(key: :read, title: "Read the issue", summary: "What broke, how often, and where to look."),
      Step.new(key: :shipped, title: "Check what shipped", summary: "Whether a release could have caused it."),
      Step.new(key: :owner, title: "Assign an owner", summary: "Make it someone's job."),
      Step.new(key: :close, title: "Close the loop", summary: "Resolve it, ignore it, or leave it open."),
      Step.new(key: :done, title: "Done", summary: "What you changed.")
    ]
  )

  ALL = [ TRIAGE ].freeze

  class << self
    def all = ALL

    def find(key)
      ALL.find { |walkthrough| walkthrough.key.to_s == key.to_s }
    end

    def for_section(section_key)
      ALL.select { |walkthrough| walkthrough.section_key == section_key.to_sym }
    end
  end

  def step(key)
    steps.find { |candidate| candidate.key.to_s == key.to_s }
  end

  # The steps listed in the rail. The last step is the finish screen.
  def rail_steps
    steps[0...-1]
  end

  def next_step(step)
    steps[steps.index(step) + 1]
  end

  def previous_step(step)
    position = steps.index(step)
    position.to_i.positive? ? steps[position - 1] : nil
  end

  # Triage needs a real issue to act on.
  def available_for?(project)
    project.error_groups.open.exists?
  end
end
