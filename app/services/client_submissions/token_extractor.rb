# frozen_string_literal: true

module ClientSubmissions
  class TokenExtractor
    Result = Data.define(:token, :source)

    def self.call(request)
      new(request).call
    end

    def initialize(request)
      @request = request
    end

    def call
      authorization = request.headers["Authorization"].to_s
      if authorization.start_with?("Bearer ")
        return Result.new(
          token: authorization.delete_prefix("Bearer ").strip,
          source: "authorization_bearer"
        )
      end

      x_api_key = request.headers["X-Api-Key"].to_s
      return Result.new(token: x_api_key.strip, source: "x_api_key") if x_api_key.present?

      Result.new(token: nil, source: nil)
    end

    private

    attr_reader :request
  end
end
