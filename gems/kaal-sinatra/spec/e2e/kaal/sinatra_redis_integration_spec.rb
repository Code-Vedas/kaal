# frozen_string_literal: true

require 'spec_helper'
require 'redis'

RSpec.describe Kaal::Sinatra, integration: :redis do
  include SinatraIntegrationHelpers

  it 'integrates a classic Sinatra app through the redis backend' do
    skip 'REDIS_URL not set' if ENV['REDIS_URL'].to_s.empty?

    namespace = "kaal-sinatra-test:classic:#{Process.pid}"
    redis = Redis.new(url: ENV.fetch('REDIS_URL'))
    redis.scan_each(match: "#{namespace}:*") { |key| redis.del(key) }

    run_dummy_app(
      :classic,
      backend: 'redis',
      app_class_name: 'Sinatra::Application',
      env: { 'REDIS_URL' => ENV.fetch('REDIS_URL'), 'KAAL_TEST_NAMESPACE' => namespace }
    ) do |app_root, _env, lines|
      expect(lines).to eq(['200', 'Kaal::Backend::RedisAdapter', 'true'])
      expect(redis.hget("#{namespace}:definitions", 'sinatra:heartbeat')).to include('"key":"sinatra:heartbeat"')
      expect(File.read(KaalSinatraDummyAppSupport.job_log_path(app_root))).not_to be_empty
    end
  ensure
    if redis && namespace
      redis.scan_each(match: "#{namespace}:*") { |key| redis.del(key) }
      redis.close
    end
  end

  it 'integrates a modular Sinatra app through the redis backend' do
    skip 'REDIS_URL not set' if ENV['REDIS_URL'].to_s.empty?

    namespace = "kaal-sinatra-test:modular:#{Process.pid}"
    redis = Redis.new(url: ENV.fetch('REDIS_URL'))
    redis.scan_each(match: "#{namespace}:*") { |key| redis.del(key) }

    run_dummy_app(
      :modular,
      backend: 'redis',
      app_class_name: 'ModularDummyApp',
      env: { 'REDIS_URL' => ENV.fetch('REDIS_URL'), 'KAAL_TEST_NAMESPACE' => namespace }
    ) do |app_root, _env, lines|
      expect(lines).to eq(['200', 'Kaal::Backend::RedisAdapter', 'true'])
      expect(redis.hget("#{namespace}:definitions", 'sinatra:heartbeat')).to include('"key":"sinatra:heartbeat"')
      expect(File.read(KaalSinatraDummyAppSupport.job_log_path(app_root))).not_to be_empty
    end
  ensure
    if redis && namespace
      redis.scan_each(match: "#{namespace}:*") { |key| redis.del(key) }
      redis.close
    end
  end
end
