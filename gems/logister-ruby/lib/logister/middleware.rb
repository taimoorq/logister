module Logister
  class Middleware
    def initialize(app)
      @app = app
    end

    def call(env)
      @app.call(env)
    rescue StandardError => e
      Logister.report_error(
        e,
        context: {
          request_id: env['action_dispatch.request_id'],
          path: env['PATH_INFO'],
          method: env['REQUEST_METHOD']
        }
      )
      raise
    end
  end
end
