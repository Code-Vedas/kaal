# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'spec_helper'

RSpec.describe Kaal::SchedulerTimeZoneResolver do
  subject(:resolver) { described_class.new(configuration: configuration) }

  let(:configuration) { Kaal::Configuration.new }

  around do |example|
    Time.use_zone(nil) { example.run }
  end

  describe '#time_zone' do
    it 'uses configuration.time_zone when present' do
      configuration.time_zone = 'America/Toronto'

      expect(resolver.time_zone.tzinfo.name).to eq('America/Toronto')
    end

    it 'falls back to Time.zone when configuration.time_zone is unset' do
      Time.use_zone('Europe/Berlin') do
        expect(resolver.time_zone.tzinfo.name).to eq('Europe/Berlin')
      end
    end

    it 'falls back to UTC when configuration.time_zone and Time.zone are unset' do
      expect(resolver.time_zone.tzinfo.name).to eq('Etc/UTC')
    end

    it 'falls back to UTC when the injected time zone provider returns nil' do
      resolver = described_class.new(configuration: configuration, time_zone_provider: -> {})

      expect(resolver.time_zone.tzinfo.name).to eq('Etc/UTC')
    end

    it 'raises ConfigurationError for an invalid configured time zone' do
      configuration.time_zone = 'Mars/Olympus'

      expect { resolver.time_zone }.to raise_error(
        Kaal::ConfigurationError,
        /Invalid time_zone configuration/
      )
    end
  end

  describe '#time_zone_identifier' do
    it 'returns a tzinfo identifier for the resolved time zone' do
      configuration.time_zone = 'America/Toronto'

      expect(resolver.time_zone_identifier).to eq('America/Toronto')
    end
  end

  describe 'provider failures' do
    subject(:resolver_with_failing_provider) do
      described_class.new(
        configuration: configuration,
        time_zone_provider: -> { raise 'provider failure' }
      )
    end

    it 'falls back to UTC when the time zone provider raises' do
      expect(resolver_with_failing_provider.time_zone.tzinfo.name).to eq('Etc/UTC')
    end
  end

  describe 'default provider' do
    it 'returns nil when Time does not expose .zone' do
      allow(Time).to receive(:respond_to?).and_call_original
      allow(Time).to receive(:respond_to?).with(:zone).and_return(false)

      expect(described_class::DEFAULT_TIME_ZONE_PROVIDER.call).to be_nil
    end
  end
end
