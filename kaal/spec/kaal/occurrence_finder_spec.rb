# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'spec_helper'

RSpec.describe Kaal::OccurrenceFinder do
  subject(:finder) { described_class.new(configuration: configuration) }

  let(:logger) { instance_spy(Logger) }
  let(:configuration) do
    Kaal::Configuration.new.tap do |config|
      config.logger = logger
    end
  end

  describe '#call' do
    it 'finds occurrences within the time window' do
      cron = Fugit.parse_cron('* * * * *')
      now = Time.now

      occurrences = finder.call(cron: cron, start_time: now - 65.seconds, end_time: now)

      expect(occurrences).to be_a(Array)
      expect(occurrences.length).to be >= 1
    end

    it 'returns empty array when no occurrences' do
      cron = Fugit.parse_cron('0 0 1 1 *')
      now = Time.now

      occurrences = finder.call(cron: cron, start_time: now, end_time: now + 1.second)

      expect(occurrences).to eq([])
    end

    it 'breaks when next_time returns nil' do
      cron = double
      allow(cron).to receive(:next_time).and_return(nil)

      occurrences = finder.call(cron: cron, start_time: Time.now, end_time: Time.now + 60)

      expect(occurrences).to eq([])
    end

    it 'breaks when next_time exceeds end_time' do
      cron = double
      allow(cron).to receive(:next_time).and_return(Time.now + 1000)

      occurrences = finder.call(cron: cron, start_time: Time.now, end_time: Time.now + 60)

      expect(occurrences).to eq([])
    end

    it 'normalizes plain Time values returned by next_time to UTC' do
      cron = double
      fire_time = Time.new(2026, 1, 15, 9, 0, 0, '-05:00')
      allow(cron).to receive(:next_time).and_return(fire_time, nil)

      occurrences = finder.call(
        cron: cron,
        start_time: Time.utc(2026, 1, 15, 13, 0, 0),
        end_time: Time.utc(2026, 1, 15, 15, 0, 0)
      )

      expect(occurrences).to eq([Time.utc(2026, 1, 15, 14, 0, 0)])
      expect(occurrences).to all(be_utc)
    end

    it 'rescues StandardError and logs it' do
      cron = double
      allow(cron).to receive(:next_time).and_raise(StandardError, 'Calc error')

      result = finder.call(cron: cron, start_time: Time.now, end_time: Time.now + 60)

      expect(result).to eq([])
      expect(logger).to have_received(:error).with(/Failed to calculate occurrences/)
    end

    it 'rescues StandardError without logging when logger is nil' do
      configuration.logger = nil
      cron = double
      allow(cron).to receive(:next_time).and_raise(StandardError, 'Calc error')

      result = finder.call(cron: cron, start_time: Time.now, end_time: Time.now + 60)

      expect(result).to eq([])
    end

    it 'uses UTC scheduling when the cron is parsed in UTC' do
      cron = Fugit.parse_cron('0 9 * * * UTC')

      occurrences = finder.call(
        cron: cron,
        start_time: Time.utc(2026, 1, 15, 8, 0, 0),
        end_time: Time.utc(2026, 1, 15, 10, 0, 0)
      )

      expect(occurrences).to eq([Time.utc(2026, 1, 15, 9, 0, 0)])
      expect(occurrences).to all(be_utc)
    end

    it 'uses the cron time zone for evaluation' do
      cron = Fugit.parse_cron('0 9 * * * America/Toronto')

      occurrences = finder.call(
        cron: cron,
        start_time: Time.utc(2026, 1, 15, 13, 0, 0),
        end_time: Time.utc(2026, 1, 15, 15, 0, 0)
      )

      expect(occurrences).to eq([Time.utc(2026, 1, 15, 14, 0, 0)])
      expect(occurrences).to all(be_utc)
    end

    it 'skips nonexistent local times during spring-forward DST transitions' do
      cron = Fugit.parse_cron('30 2 * * * America/Toronto')

      occurrences = finder.call(
        cron: cron,
        start_time: Time.utc(2026, 3, 8, 0, 0, 0),
        end_time: Time.utc(2026, 3, 8, 23, 59, 59)
      )

      expect(occurrences).to eq([])
    end

    it 'includes both repeated local times during fall-back DST transitions' do
      cron = Fugit.parse_cron('30 1 * * * America/Toronto')

      occurrences = finder.call(
        cron: cron,
        start_time: Time.utc(2026, 11, 1, 0, 0, 0),
        end_time: Time.utc(2026, 11, 1, 23, 59, 59)
      )

      expect(occurrences).to eq([
                                  Time.utc(2026, 11, 1, 5, 30, 0),
                                  Time.utc(2026, 11, 1, 6, 30, 0)
                                ])
    end

    it 'returns multiple occurrences across the window' do
      cron = Fugit.parse_cron('*/5 * * * * UTC')
      start_time = Time.now.floor
      end_time = start_time + 20.minutes

      occurrences = finder.call(cron: cron, start_time: start_time, end_time: end_time)

      expect(occurrences.length).to be >= 4
    end

    it 'increments time correctly across repeated scans' do
      cron = Fugit.parse_cron('* * * * * UTC')
      now = Time.now
      start_time = now.floor
      end_time = start_time + 2.minutes

      occurrences = finder.call(cron: cron, start_time: start_time, end_time: end_time)

      expect(occurrences.count).to be >= 2
      expect((occurrences[1] - occurrences[0]).to_i).to be >= 60 if occurrences.length >= 2
    end

    it 'respects the exact end_time boundary' do
      cron = Fugit.parse_cron('* * * * * UTC')
      now = Time.now
      start_time = now - 1.minute
      end_time = start_time + 59.seconds

      occurrences = finder.call(cron: cron, start_time: start_time, end_time: end_time)

      expect(occurrences).to all(be <= end_time)
    end

    it 'continues to the next iteration for multiple matches' do
      cron = Fugit.parse_cron('* * * * * UTC')
      start_time = (Time.now - 5.minutes).floor
      end_time = start_time + 5.minutes

      occurrences = finder.call(cron: cron, start_time: start_time, end_time: end_time)

      expect(occurrences.length).to be > 1
      expect(occurrences.uniq.length).to eq(occurrences.length)
    end
  end
end
