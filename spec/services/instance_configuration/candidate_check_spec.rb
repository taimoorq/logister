# frozen_string_literal: true

require "rails_helper"

RSpec.describe InstanceConfiguration::CandidateCheck, type: :model do
  let(:admin) { users(:one) }

  def save(section, values)
    InstanceConfiguration.save_section!(section, values: values, clear_keys: [], actor: admin)
  end

  around do |example|
    keys = %w[SES_SMTP_PASSWORD LOGISTER_CLICKHOUSE_URL]
    original = keys.to_h { |key| [ key, ENV[key] ] }
    keys.each { |key| ENV.delete(key) }
    example.run
  ensure
    original.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  describe "saved secret destinations" do
    before do
      save("email", "email.smtp_address" => "smtp.example.com", "email.smtp_password" => "saved-password")
    end

    it "requires the SMTP password again when the server changes" do
      check = described_class.call("email", values: { "email.smtp_address" => "smtp.attacker.test", "email.smtp_password" => "" })

      expect(check).not_to be_valid
      expect(check.errors.to_sentence).to include("Re-enter SMTP password", "SMTP server")
      expect(check.errors.to_sentence).not_to include("saved-password")
    end

    it "treats port, region, and STARTTLS changes as destination changes" do
      expect(described_class.call("email", values: { "email.smtp_port" => "2525" })).not_to be_valid
      expect(described_class.call("email", values: { "email.starttls" => "0" })).not_to be_valid
    end

    it "accepts a changed server when the password is re-entered" do
      check = described_class.call("email", values: { "email.smtp_address" => "smtp.new.example.com", "email.smtp_password" => "new-password" })

      expect(check).to be_valid
      expect(check.destination_host).to eq("smtp.new.example.com")
    end

    it "accepts unchanged destinations without the saved password" do
      check = described_class.call("email", values: { "email.smtp_address" => "smtp.example.com", "email.smtp_username" => "mailer" })

      expect(check).to be_valid
    end

    it "accepts a changed server when the saved password is being cleared" do
      check = described_class.call(
        "email",
        values: { "email.smtp_address" => "smtp.other.example.com" },
        clear_keys: [ "email.smtp_password" ]
      )

      expect(check).to be_valid
    end

    it "refuses a changed server when the password comes from the environment" do
      ENV["SES_SMTP_PASSWORD"] = "environment-password"

      check = described_class.call("email", values: { "email.smtp_address" => "smtp.other.example.com", "email.smtp_password" => "typed" })

      expect(check).not_to be_valid
      expect(check.errors.to_sentence).to include("SES_SMTP_PASSWORD", "in the environment")
    end

    it "guards archive, GitHub, and self-monitoring secrets the same way" do
      save("archive_storage", "archive_storage.secret_access_key" => "aws-secret")
      save("github", "github.private_key" => "pem")
      save("observability", "observability.api_key" => "project-key")

      expect(described_class.call("archive_storage", values: { "archive_storage.endpoint" => "https://s3.attacker.test" })).not_to be_valid
      expect(described_class.call("github", values: { "github.api_url" => "https://api.attacker.test" })).not_to be_valid
      expect(described_class.call("observability", values: { "observability.endpoint" => "https://attacker.test/api/v1/ingest_events" })).not_to be_valid
    end
  end

  describe "ClickHouse transport" do
    it "refuses a plain HTTP endpoint with a password on a remote host" do
      check = described_class.call(
        "clickhouse",
        values: { "clickhouse.url" => "http://clickhouse.example.com:8123", "clickhouse.password" => "secret" },
        operation: :test
      )

      expect(check).not_to be_valid
      expect(check.errors.to_sentence).to include("https://")
    end

    it "allows plain HTTP for loopback hosts and HTTPS for remote hosts" do
      %w[http://127.0.0.1:8123 http://localhost:8123 http://[::1]:8123 https://clickhouse.example.com:8443].each do |url|
        check = described_class.call("clickhouse", values: { "clickhouse.url" => url, "clickhouse.password" => "secret" }, operation: :test)

        expect(check).to be_valid, "expected #{url} to be accepted"
      end
    end

    it "allows plain HTTP without a password" do
      check = described_class.call("clickhouse", values: { "clickhouse.url" => "http://clickhouse:8123" }, operation: :test)

      expect(check).to be_valid
    end

    it "trusts an endpoint supplied by the environment" do
      ENV["LOGISTER_CLICKHOUSE_URL"] = "http://clickhouse:8123"

      check = described_class.call("clickhouse", values: { "clickhouse.password" => "secret" }, operation: :test)

      expect(check).to be_valid
    end

    it "does not block unrelated saves of an existing HTTP configuration" do
      save("clickhouse", "clickhouse.url" => "http://clickhouse:8123", "clickhouse.password" => "secret")

      expect(described_class.call("clickhouse", values: { "clickhouse.failure_throttle_seconds" => "90" })).to be_valid
      expect(described_class.call("clickhouse", values: { "clickhouse.failure_throttle_seconds" => "90" }, operation: :test)).not_to be_valid
    end
  end

  describe "URL settings" do
    it "rejects non-HTTP and host-less URLs" do
      [ "javascript:alert(1)", "//evil.example", "data:text/javascript,alert(1)", "https://", "not a url" ].each do |value|
        check = described_class.call("public_site", values: { "public_site.cookie_banner_script_url" => value })

        expect(check).not_to be_valid, "expected #{value.inspect} to be rejected"
        expect(check.errors.to_sentence).to include("Banner script URL must be an http:// or https:// URL")
      end

      expect(described_class.call("general", values: { "general.docs_url" => "ftp://docs.example.com" })).not_to be_valid
    end

    it "accepts HTTP(S) URLs and blank values" do
      check = described_class.call(
        "public_site",
        values: { "public_site.cookie_banner_script_url" => "https://cdn.example.com/banner.js", "public_site.cookie_banner_base_url" => "" }
      )

      expect(check).to be_valid
    end
  end

  describe "registration domains" do
    it "requires at least one valid domain for allowed-domain sign-up" do
      empty = described_class.call("authentication", values: { "authentication.registration_mode" => "allowed_domains" })
      invalid = described_class.call(
        "authentication",
        values: { "authentication.registration_mode" => "allowed_domains", "authentication.registration_allowed_domains" => "example.com, not_a_domain" }
      )
      valid = described_class.call(
        "authentication",
        values: { "authentication.registration_mode" => "allowed_domains", "authentication.registration_allowed_domains" => "Example.com, @example.org" }
      )

      expect(empty.errors.to_sentence).to include("Add at least one allowed sign-up domain")
      expect(invalid.errors.to_sentence).to include("not_a_domain")
      expect(valid).to be_valid
    end
  end
end
