# frozen_string_literal: true

# Instance-level services that some setup steps depend on. A project user cannot
# fix these, so a step that is waiting on one shows as blocked and names the
# Logister admin as the owner.
class ProjectSetupPrerequisites
  Check = Data.define(:key, :label, :met, :message, :admin_section)

  # Which prerequisite each step needs before it can work.
  BY_STEP = {
    alerts: :email,
    source_repo: :github_app,
    linked_projects: :correlations,
    archive_exports: :archive_storage
  }.freeze

  def self.for_step(step_key)
    key = BY_STEP[step_key.to_sym]
    key && check(key)
  end

  def self.check(key)
    case key.to_sym
    when :email
      Check.new(
        key: :email,
        label: "Outbound email",
        met: email_configured?,
        message: "Outbound email isn't set up on this Logister instance, so alerts can't be delivered yet.",
        admin_section: "email"
      )
    when :github_app
      Check.new(
        key: :github_app,
        label: "GitHub App",
        met: Logister::GithubAppConfig.configured?,
        message: "The GitHub App isn't set up on this Logister instance, so repositories can't be connected yet.",
        admin_section: "github"
      )
    when :correlations
      Check.new(
        key: :correlations,
        label: "Cross-project correlations",
        met: ProjectCorrelationPolicy.instance_enabled?,
        message: "Cross-project correlations are turned off for this Logister instance.",
        admin_section: nil
      )
    when :archive_storage
      Check.new(
        key: :archive_storage,
        label: "Archive storage",
        met: archive_storage_ready?,
        message: "Archive storage is set to S3 but no bucket is configured on this Logister instance.",
        admin_section: "archive_storage"
      )
    else
      raise ArgumentError, "Unknown setup prerequisite: #{key}"
    end
  end

  def self.email_configured?
    InstanceConfiguration.value("email.smtp_username").present? &&
      InstanceConfiguration.value("email.smtp_password").present?
  end

  def self.archive_storage_ready?
    return true unless InstanceConfiguration.value("archive_storage.service") == "s3"

    InstanceConfiguration.value("archive_storage.bucket").present?
  end
end
