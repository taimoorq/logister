# frozen_string_literal: true

class ProjectDeploymentLinks
  def initialize(deployment)
    @deployment = deployment
  end

  def short_commit_sha
    deployment.commit_sha.to_s.first(7)
  end

  def github_commit_url
    return if deployment.repository_full_name.blank? || deployment.commit_sha.blank?

    "#{Logister::GithubAppConfig.web_url}/#{deployment.repository_full_name}/commit/#{deployment.commit_sha}"
  end

  def pull_request_number
    metadata_value("pull_request_number")
  end

  def pull_request_url
    metadata_value("pull_request_url").presence || inferred_pull_request_url
  end

  def pull_request_label
    return if pull_request_number.blank?

    "PR ##{pull_request_number}"
  end

  def release_url
    metadata_value("release_url").presence || inferred_release_url
  end

  def release_tag
    metadata_value("release_tag").presence || deployment.release
  end

  def compare_url(previous_deployment)
    return if previous_deployment.blank?
    return unless previous_deployment.repository_full_name == deployment.repository_full_name
    return if previous_deployment.commit_sha.blank? || deployment.commit_sha.blank?

    "#{Logister::GithubAppConfig.web_url}/#{deployment.repository_full_name}/compare/#{previous_deployment.commit_sha}...#{deployment.commit_sha}"
  end

  private

  attr_reader :deployment

  def metadata_value(key)
    deployment.metadata.is_a?(Hash) ? deployment.metadata[key] || deployment.metadata[key.to_sym] : nil
  end

  def inferred_pull_request_url
    return if deployment.repository_full_name.blank? || pull_request_number.blank?

    "#{Logister::GithubAppConfig.web_url}/#{deployment.repository_full_name}/pull/#{pull_request_number}"
  end

  def inferred_release_url
    return if deployment.repository_full_name.blank? || release_tag.blank?

    "#{Logister::GithubAppConfig.web_url}/#{deployment.repository_full_name}/releases/tag/#{ERB::Util.url_encode(release_tag)}"
  end
end
