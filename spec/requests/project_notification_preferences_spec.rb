# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Project notification preferences", type: :request do
  describe "PATCH /projects/:uuid/notification_preference" do
    it "updates the current user's project email settings" do
      sign_in users(:one)

      patch project_notification_preference_path(projects(:one)), params: {
        project_notification_preference: {
          first_occurrence_enabled: "0",
          digest_frequency: "weekly",
          digest_send_hour: "14",
          time_zone: "Eastern Time (US & Canada)"
        }
      }

      expect(response).to redirect_to(settings_project_path(projects(:one), anchor: "notifications"))
      preference = ProjectNotificationPreference.find_by!(project: projects(:one), user: users(:one))
      expect(preference.first_occurrence_enabled).to be false
      expect(preference.digest_frequency).to eq("weekly")
      expect(preference.digest_send_hour).to eq(14)
      expect(preference.time_zone).to eq("Eastern Time (US & Canada)")
    end
  end

  describe "POST /notification_preferences/unsubscribe/:token" do
    it "disables project email notifications without requiring a signed-in user" do
      preference = create(:project_notification_preference, :daily)

      post unsubscribe_notification_preferences_path(token: preference.unsubscribe_token)

      expect(response).to have_http_status(:ok)
      expect(preference.reload.first_occurrence_enabled).to be false
      expect(preference.digest_frequency).to eq("none")
    end
  end
end
