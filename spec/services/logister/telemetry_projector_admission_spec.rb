# frozen_string_literal: true

require "rails_helper"
require "sidekiq/redis_connection"
require "socket"
require "tmpdir"

RSpec.describe Logister::TelemetryProjectorAdmission do
  let(:admission) { described_class.new }
  let(:keys) { described_class::KEYS }

  around do |example|
    Dir.mktmpdir("logister-projector-admission") do |directory|
      socket = TCPServer.new("127.0.0.1", 0)
      port = socket.addr[1]
      socket.close
      log = File.join(directory, "redis.log")
      pid = Process.spawn("redis-server", "--bind", "127.0.0.1", "--port", port.to_s,
        "--save", "", "--appendonly", "no", out: log, err: [ :child, :out ])
      url = "redis://127.0.0.1:#{port}/0"
      @redis = Redis.new(url: url, connect_timeout: 1, read_timeout: 1)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
      loop do
        break if @redis.ping == "PONG" rescue nil
        raise "Redis did not start" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

        sleep 0.01
      end
      @pool = Sidekiq::RedisConnection.create(url: url, size: 5)
      previous_adapter = TelemetryProjectorJob.queue_adapter
      TelemetryProjectorJob.queue_adapter = :sidekiq
      Sidekiq::Client.via(@pool) { example.run }
    ensure
      TelemetryProjectorJob.queue_adapter = previous_adapter if previous_adapter
      @pool&.shutdown(&:close)
      @redis&.close
      Process.kill("TERM", pid) if pid
      Process.wait(pid) if pid
    end
  end

  before { allow(Sidekiq).to receive(:redis).and_yield(@redis) }

  it "admits a flood as one native argument-free job and retains its marker during a worker outage" do
    threads = 10.times.map do
      Thread.new { Sidekiq::Client.via(@pool) { 30.times { admission.wake } } }
    end
    threads.each(&:value)
    queued = @redis.lrange("queue:projector", 0, -1)
    expect(queued.length).to eq(1)
    envelope = JSON.parse(queued.first).fetch("args").first
    expect(envelope).to include("job_class" => "TelemetryProjectorJob", "arguments" => [])
    expect(@redis.hget(keys[1], "job_id")).to eq(envelope.fetch("job_id"))
    expect(@redis.ttl(keys[1])).to eq(-1)

    3.times do
      age_reservation
      @redis.del(described_class::RECOVERY_KEY)
      admission.recover
    end
    expect(@redis.llen("queue:projector")).to eq(1)
  end

  it "limits running owners, coalesces saturated wakes, and carries a wake across the final-empty race" do
    sessions = 3.times.map { admission.enter(SecureRandom.uuid) }
    expect(sessions).to all(be_a(described_class::Session))
    expect(admission.enter("legacy-excess-hint")).to be_nil
    100.times { expect(admission.wake).to be(false) }
    expect(@redis.llen("queue:projector")).to eq(0)

    # Work arrived after the drainer's empty PG query but before its release.
    sessions.first.finish(work_left: false)
    expect(@redis.llen("queue:projector")).to eq(1)
    sessions.drop(1).each { |session| session.finish(work_left: false) }
    expect(@redis.llen("queue:projector")).to eq(1)
    job = pop_job
    admission.enter(job.fetch("job_id")).finish(work_left: false)
    expect(@redis.llen("queue:projector")).to eq(0)
  end

  it "leaves the new carrier intact when an old argument-free hint enters" do
    admission.wake
    marker = @redis.hget(keys[1], "job_id")
    admission.enter("legacy-job").finish(work_left: true)
    expect(@redis.hget(keys[1], "job_id")).to eq(marker)
    expect(@redis.llen("queue:projector")).to eq(1)
  end

  it "recovers enqueue failure without flooding and never falls back on Redis failure" do
    allow_any_instance_of(TelemetryProjectorJob).to receive(:enqueue).and_raise(ActiveJob::EnqueueError, "failed")
    expect(admission.wake).to be(false)
    expect(@redis.exists?(keys[1])).to be(false)
    expect(@redis.get(keys[0]).to_i).to eq(1)
    allow_any_instance_of(TelemetryProjectorJob).to receive(:enqueue).and_call_original
    admission.recover
    expect(@redis.llen("queue:projector")).to eq(1)

    allow(Sidekiq).to receive(:redis).and_raise(Redis::CannotConnectError)
    expect(TelemetryProjectorJob).not_to receive(:perform_later)
    10.times { expect(admission.wake).to be(false) }
  end

  it "recovers a producer crash between reservation and publication and fences the late producer" do
    old_job = TelemetryProjectorJob.new
    expect(admission.send(:command, "wake", job: old_job.job_id)).to eq(1)
    age_reservation
    admission.recover
    expect(@redis.llen("queue:projector")).to eq(1)
    expect(admission.send(:publish, old_job)).to be(false)
    expect(pop_job.fetch("job_id")).not_to eq(old_job.job_id)
  end

  it "retains reservations when a bounded scan cannot prove the carrier is absent" do
    admission.send(:command, "wake", job: "reserved")
    @redis.lpush("queue:projector", "invalid-json")
    age_reservation
    admission.recover
    expect(@redis.hget(keys[1], "job_id")).to eq("reserved")
    @redis.del("queue:projector", described_class::RECOVERY_KEY)
    1_001.times { @redis.lpush("queue:projector", '{"args":[]}') }
    admission.recover
    expect(@redis.hget(keys[1], "job_id")).to eq("reserved")
  end

  it "fences late renewal and release after expiry even when the job ID is retried" do
    old = admission.enter("same-job-id")
    owner = @redis.zrange(keys[2], 0, -1).sole
    @redis.zadd(keys[2], 0, owner)
    current = admission.enter("same-job-id")
    expect(old.heartbeat(force: true)).to be(false)
    old.finish(work_left: true)
    expect(@redis.zcard(keys[2])).to eq(1)
    expect(@redis.llen("queue:projector")).to eq(0)
    expect(current.heartbeat(force: true)).to be(true)
    current.finish(work_left: true)
    expect(@redis.llen("queue:projector")).to eq(1)
  end

  it "recovers Redis state loss and does not resurrect a session after a heartbeat failure" do
    old = admission.enter("old")
    @redis.del(*keys)
    expect(old.heartbeat(force: true)).to be(false)
    admission.recover
    expect(@redis.llen("queue:projector")).to eq(1)
    current = admission.enter(pop_job.fetch("job_id"))
    expect(current.heartbeat(force: true)).to be(true)
    expect(old.heartbeat(force: true)).to be(false)
  end

  it "backs off a failed drainer instead of creating an immediate retry loop during an outage" do
    session = admission.enter("dependency-failure")
    10.times { admission.wake }
    session.finish(work_left: true, failed: true)
    queued_before = @redis.llen("queue:projector")
    100.times { expect(admission.wake).to be(false) }
    expect(admission.enter("old-hint")).to be_nil
    expect(@redis.llen("queue:projector")).to eq(queued_before)
    expect(@redis.ttl(keys[3])).to be_between(1, 10)
    @redis.del(keys[3]) # Advance the recovery boundary without waiting ten seconds.
    expect(admission.enter(pop_job.fetch("job_id"))).to be_a(described_class::Session)
  end

  def age_reservation
    @redis.hset(keys[1], "reserved_at", @redis.time.first - 120)
  end

  def pop_job
    JSON.parse(@redis.rpop("queue:projector")).fetch("args").first
  end
end
