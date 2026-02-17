require 'json'
require 'net/http'
require 'uri'

module Logister
  class Client
    def initialize(configuration)
      @configuration = configuration
      @worker_mutex = Mutex.new
      @queue = SizedQueue.new(@configuration.queue_size)
      @worker = nil
      @running = false
    end

    def publish(payload)
      return false unless ready?

      return publish_sync(payload) unless @configuration.async

      ensure_worker_started
      enqueue(payload)
    end

    def flush(timeout: 2)
      return true unless @configuration.async

      started_at = monotonic_now
      while @queue.length.positive?
        return false if monotonic_now - started_at > timeout

        sleep(0.01)
      end

      true
    end

    def shutdown
      return true unless @configuration.async

      @running = false
      begin
        @queue.push(nil)
      rescue StandardError
        nil
      end
      @worker&.join(1)
      true
    end

    private

    def enqueue(payload)
      @queue.push(payload, true)
      true
    rescue ThreadError
      @configuration.logger.warn('logister queue full; dropping event')
      false
    end

    def ensure_worker_started
      return if @running && @worker&.alive?

      @worker_mutex.synchronize do
        return if @running && @worker&.alive?

        @running = true
        @worker = Thread.new { run_worker }
      end
    end

    def run_worker
      while @running
        payload = @queue.pop
        break if payload.nil?

        publish_sync(payload)
      end
    rescue StandardError => e
      @configuration.logger.warn("logister worker crashed: #{e.class} #{e.message}")
      @running = false
    end

    def publish_sync(payload)
      attempts = 0
      begin
        attempts += 1
        send_request(payload)
      rescue StandardError => e
        if attempts <= @configuration.max_retries
          sleep(@configuration.retry_base_interval * (2**(attempts - 1)))
          retry
        end

        @configuration.logger.warn("logister publish failed: #{e.class} #{e.message}")
        false
      end
    end

    def send_request(payload)
      uri = URI.parse(@configuration.endpoint)
      request = Net::HTTP::Post.new(uri)
      request['Content-Type'] = 'application/json'
      request['Authorization'] = "Bearer #{@configuration.api_key}"
      request.body = { event: payload }.to_json

      response = Net::HTTP.start(
        uri.host,
        uri.port,
        use_ssl: uri.scheme == 'https',
        open_timeout: @configuration.timeout_seconds,
        read_timeout: @configuration.timeout_seconds
      ) { |http| http.request(request) }

      return true if response.is_a?(Net::HTTPSuccess)

      raise "HTTP #{response.code}"
    end

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def ready?
      @configuration.enabled && @configuration.api_key.to_s != ''
    end
  end
end
