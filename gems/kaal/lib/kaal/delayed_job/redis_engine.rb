# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'json'
require 'time'
require 'kaal/delayed_job/registry'

module Kaal
  module DelayedJob
    # Redis-backed delayed-job store using a sorted set plus payload hash.
    class RedisEngine < Registry
      def initialize(redis, namespace: 'kaal')
        super()
        @redis = redis
        @namespace = namespace
      end

      def enqueue(job_id:, run_at:, job_class:, args:, queue: nil, **)
        payload = JSON.generate(
          job_id: job_id,
          run_at: run_at.iso8601,
          job_class: job_class,
          args: args,
          queue: queue,
          created_at: Time.now.utc.iso8601
        )

        script = <<~LUA
          if redis.call('HEXISTS', KEYS[1], ARGV[1]) == 1 then
            return 0
          end

          redis.call('HSET', KEYS[1], ARGV[1], ARGV[2])
          redis.call('ZADD', KEYS[2], ARGV[3], ARGV[1])
          return 1
        LUA

        result = @redis.eval(script, keys: [payloads_key, schedule_key], argv: [job_id, payload, run_at.to_f])
        raise DuplicateJobError, "Delayed job #{job_id.inspect} already exists" unless [1, '1', true].include?(result)

        find_job(job_id)
      end

      def pop_due(now:, limit:)
        script = <<~LUA
          local job_ids = redis.call('ZRANGEBYSCORE', KEYS[2], '-inf', ARGV[1], 'LIMIT', 0, ARGV[2])
          local payloads = {}

          for _, job_id in ipairs(job_ids) do
            if redis.call('ZREM', KEYS[2], job_id) == 1 then
              local payload = redis.call('HGET', KEYS[1], job_id)
              if payload then
                redis.call('HDEL', KEYS[1], job_id)
                table.insert(payloads, payload)
              end
            end
          end

          return payloads
        LUA

        Array(@redis.eval(script, keys: [payloads_key, schedule_key], argv: [now.to_f, limit])).filter_map do |raw|
          self.class.deserialize(raw)
        end
      end

      def find_job(job_id)
        self.class.deserialize(@redis.hget(payloads_key, job_id))
      end

      def all_jobs
        Array(@redis.zrange(schedule_key, 0, -1)).filter_map { |job_id| find_job(job_id) }
      end

      def claim_strategy
        :atomic_pop
      end

      def self.deserialize(raw)
        return nil unless raw

        parsed = JSON.parse(raw)
        run_at = parse_time(parsed['run_at'])
        created_at = parse_time(parsed['created_at'])
        return nil unless run_at && created_at

        {
          job_id: parsed['job_id'],
          run_at: run_at,
          job_class: parsed['job_class'],
          args: parsed['args'] || [],
          queue: parsed['queue'],
          created_at: created_at
        }
      rescue JSON::ParserError
        nil
      end

      def self.parse_time(value)
        Time.iso8601(value.to_s)
      rescue ArgumentError
        nil
      end

      private

      def payloads_key
        "#{@namespace}:delayed_jobs:payloads"
      end

      def schedule_key
        "#{@namespace}:delayed_jobs:schedule"
      end
    end
  end
end
