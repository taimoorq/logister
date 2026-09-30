# frozen_string_literal: true

# What the wizard layout shows around a focused path: who or what it is for, the
# one way out, and how far along the path is. Setup paths and project creation
# share the layout, so each builds its own frame.
class WizardFrame < Data.define(:context, :detail, :exit_label, :exit_path, :progress_label, :done, :total)
  def percent
    total.zero? ? 0 : (done * 100.0 / total).round
  end
end
