module Logister
  class CloudflarePagesImporter
    Result = Data.define(:status, :reason, :setting) do
      def imported? = status == :imported
      def skipped? = status == :skipped
    end

    def self.call(setting)
      new(setting).call
    end

    def initialize(setting)
      @setting = setting
    end

    def call
      return Result.new(status: :skipped, reason: :missing_setting, setting: nil) unless setting
      return Result.new(status: :skipped, reason: :wrong_provider, setting: setting) unless setting.provider_cloudflare_pages?
      return Result.new(status: :skipped, reason: :not_configured, setting: setting) unless setting.configured?

      # The API fetcher lands here next. Keeping the job/service boundary now
      # lets settings, scheduling, and result handling settle before credentials
      # or Cloudflare API calls enter the code path.
      Result.new(status: :skipped, reason: :fetcher_not_implemented, setting: setting)
    end

    private

    attr_reader :setting
  end
end
