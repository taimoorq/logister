# frozen_string_literal: true

class AddOnboardingRequiredToInstallations < ActiveRecord::Migration[8.0]
  def change
    add_column :installations, :onboarding_required, :boolean, default: false, null: false
  end
end
