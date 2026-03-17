# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Kaal::Configuration do
  describe Kaal::Configuration do
    subject(:configuration) { described_class.new }

    it 'normalizes values into the exported hash' do
      configuration.tick_interval = '10'
      configuration.window_lookback = '20'
      configuration.window_lookahead = '3'
      configuration.lease_ttl = '30'
      configuration.namespace = :ops
      configuration.time_zone = :utc
      configuration.enable_log_dispatch_registry = 'yes'
      configuration.scheduler_conflict_policy = 'code_wins'
      configuration.scheduler_missing_file_policy = 'error'

      expect(configuration.to_h).to include(
        tick_interval: 10,
        window_lookback: 20,
        window_lookahead: 3,
        lease_ttl: 30,
        namespace: 'ops',
        time_zone: 'utc',
        enable_log_dispatch_registry: true,
        scheduler_conflict_policy: :code_wins,
        scheduler_missing_file_policy: :error
      )
    end

    it 'serializes named backend and logger classes' do
      configuration.backend = Kaal::Backend::MemoryAdapter.new
      configuration.logger = Logger.new(StringIO.new)

      expect(configuration.to_h).to include(
        backend: 'Kaal::Backend::MemoryAdapter',
        logger: 'Logger'
      )
    end

    it 'keeps nil backend, logger, and time zone values in the exported hash' do
      expect(configuration.to_h).to include(backend: nil, logger: nil, time_zone: nil)
    end

    it 'normalizes falsey booleans and nil policies' do
      configuration.enable_log_dispatch_registry = nil
      configuration.time_zone = nil
      configuration.scheduler_conflict_policy = nil
      configuration.scheduler_missing_file_policy = nil

      expect(configuration.to_h).to include(
        enable_log_dispatch_registry: false,
        time_zone: nil,
        scheduler_conflict_policy: nil,
        scheduler_missing_file_policy: nil
      )
    end

    it 'returns unknown keys unchanged in private normalization' do
      expect(configuration.send(:normalize_value, :unknown_key, 123)).to eq(123)
    end

    it 'supports respond_to? for known configuration keys' do
      expect(configuration.respond_to?(:tick_interval)).to be(true)
      expect(configuration.respond_to?(:tick_interval=)).to be(true)
      expect(configuration.respond_to?(:unknown_key)).to be(false)
      expect { configuration.unknown_key }.to raise_error(NoMethodError)
    end

    it 'validates a healthy configuration' do
      expect(configuration.validate).to eq([])
      expect(configuration.validate!).to be(configuration)
    end

    it 'reports all invalid configuration values' do
      configuration.tick_interval = 0
      configuration.window_lookback = -1
      configuration.window_lookahead = -1
      configuration.lease_ttl = 0
      configuration.namespace = ' '
      configuration.scheduler_config_path = ' '
      configuration.scheduler_conflict_policy = :invalid
      configuration.scheduler_missing_file_policy = :invalid

      errors = configuration.validate

      expect(errors).to include(a_string_matching('tick_interval must be greater than 0'))
      expect(errors).to include(a_string_matching('window_lookback must be greater than or equal to 0'))
      expect(errors).to include(a_string_matching('window_lookahead must be greater than or equal to 0'))
      expect(errors).to include(a_string_matching('lease_ttl must be greater than 0'))
      expect(errors).to include('namespace cannot be blank')
      expect(errors).to include('scheduler_config_path cannot be blank')
      expect(errors).to include('scheduler_conflict_policy must be :error, :code_wins, or :file_wins')
      expect(errors).to include('scheduler_missing_file_policy must be :warn or :error')
      expect { configuration.validate! }.to raise_error(Kaal::ConfigurationError)
    end

    it 'validates lease ttl against the dispatch window' do
      configuration.window_lookback = 120
      configuration.tick_interval = 5
      configuration.lease_ttl = 124

      expect(configuration.validate).to include(
        'lease_ttl (124s) must be >= window_lookback + tick_interval (125s) to prevent duplicate dispatch'
      )
    end
  end

  describe Kaal::SchedulerTimeZoneResolver do
    subject(:resolver) { described_class.new(configuration: configuration) }

    let(:configuration) { Kaal::Configuration.new }

    it 'defaults to utc' do
      expect(resolver.time_zone_identifier).to eq('UTC')
    end

    it 'returns a configured time zone' do
      configuration.time_zone = 'America/Toronto'

      expect(resolver.time_zone_identifier).to eq('America/Toronto')
    end

    it 'raises for invalid time zone identifiers' do
      configuration.time_zone = 'Nope/Zone'

      expect { resolver.time_zone_identifier }.to raise_error(Kaal::ConfigurationError, /Invalid time_zone configuration/)
    end
  end

  describe Kaal::CronUtils do
    it 'validates expressions and macros' do
      expect(described_class.valid?('@daily')).to be(true)
      expect(described_class.valid?('*/15 * * * *')).to be(true)
      expect(described_class.valid?('')).to be(false)
      expect(described_class.valid?('bad cron')).to be(false)
    end

    it 'simplifies canonical expressions and macros' do
      expect(described_class.simplify(' 0 0 * * * ')).to eq('@daily')
      expect(described_class.simplify('@DAILY')).to eq('@daily')
    end

    it 'raises for invalid simplify inputs' do
      expect { described_class.simplify('@unsupported') }.to raise_error(ArgumentError, /Unsupported cron macro/)
      expect { described_class.simplify('') }.to raise_error(ArgumentError, /Invalid cron expression/)
    end

    it 'lints valid and invalid macros' do
      expect(described_class.lint('@daily')).to eq([])
      expect(described_class.lint('@unsupported')).to include(/Unsupported cron macro/)
    end

    it 'lints bad field counts and out-of-range values' do
      expect(described_class.lint('1 2 3')).to include(/Expected 5 fields/)
      expect(described_class.lint('*/100 * * * *')).to include(/minute step '100' is out of range/)
      expect(described_class.lint('61 * * * *')).to include(/minute value '61' is out of range/)
    end

    it 'lints malformed ranges and base-step segments' do
      expect(described_class.lint('5-1 * * * *')).to include(/start greater than end/)
      expect(described_class.lint('1-5/10 * * * *')).to include(%r{step '10' is out of range for range '1-5/10'})
      expect(described_class.lint('jan/0 * * * *')).to include(%r{minute value 'jan/0' contains an out-of-range value})
    end

    it 'covers normalization rescue and additional lint branches' do
      broken_value = Object.new
      broken_value.define_singleton_method(:to_s) { raise 'boom' }

      expect(described_class.safe_normalize_expression(broken_value)).to be_nil
      expect { described_class.simplify(broken_value) }.to raise_error(ArgumentError, /Invalid cron expression/)
      expect(described_class.lint(broken_value)).to include(/Invalid cron expression/)
      expect(described_class.lint('1-5 * * * *')).to eq([])
      expect(described_class.lint('*/1 * * * *')).to eq([])
      expect(described_class.lint('1/1 * * * *')).to eq([])
      expect(described_class.lint('1/0 * * * *')).to include(/Allowed step: 1 or greater/)
      expect(described_class.lint('jan * * * *')).to include(/minute value 'jan' is out of range/)
      expect(described_class.lint('')).to include(/Invalid cron expression/)
      expect(described_class.lint('5 * * * *')).to eq([])
      expect(described_class.lint('60-61 * * * *')).to include(/contains an out-of-range value/)
      expect(described_class.lint('1-5/1 * * * *')).to eq([])
      expect(described_class.send(:parse_value, 'jan', { names: { 'jan' => 1 }, min: 1, max: 12 })).to eq(1)
    end
  end

  describe Kaal::CronHumanizer do
    before do
      I18n.load_path = [File.expand_path('../../config/locales/en.yml', __dir__)]
      I18n.backend.load_translations
    end

    it 'humanizes common macros and schedules' do
      expect(described_class.to_human('@daily')).to eq('Daily')
      expect(described_class.to_human('*/15 * * * *')).to eq('Every 15 minutes')
      expect(described_class.to_human('0 9 * * 1')).to eq('At 09:00 every Monday')
      expect(described_class.to_human('0 9 * * *')).to eq('At 09:00 every day')
      expect(described_class.to_human('1 2 3 4 5')).to eq('Cron: 1 2 3 4 5')
    end

    it 'raises for invalid expressions' do
      expect { described_class.to_human('@invalid') }.to raise_error(ArgumentError, /Unsupported cron macro/)
      expect { described_class.to_human('') }.to raise_error(ArgumentError, /Invalid cron expression/)
    end

    it 'covers fallback and helper branches' do
      allow(I18n).to receive(:t).and_call_original
      allow(I18n).to receive(:t).with('kaal.phrases.cron_expression', expression: '1 2 3 4 5').and_return('')

      expect(described_class.to_human('1 2 3 4 5')).to eq('')
      expect { described_class.send(:humanize_expression, 'bad cron') }.to raise_error(ArgumentError, /Invalid cron expression/)
      expect(described_class.send(:humanize_macro, '@annually')).to eq('Yearly')
      expect(described_class.send(:weekday_name, 7)).to eq('Sunday')
      expect(described_class.send(:interval_unit, 1, singular: 'minute', plural: 'minutes')).to eq('minute')
      expect(described_class.send(:derive_interval, [1, 2, 3])).to be_nil
      expect(described_class.send(:derive_interval, [0, 2, 5])).to be_nil
      expect(described_class.send(:extract_weekday, [[1, 2]])).to be_nil
      expect(described_class.send(:extract_weekday, 'mon')).to be_nil
      expect(described_class.send(:at_time_weekday_phrase, Fugit.parse_cron('0 9 1 * 1'))).to be_nil
      expect(described_class.send(:at_time_daily_phrase, Fugit.parse_cron('0 9 1 * *'))).to be_nil
      expect(described_class.send(:every_minute_interval_phrase, Fugit.parse_cron('1,2,3 * * * *'))).to be_nil
      expect(described_class.send(:every_minute_interval_phrase, Fugit.parse_cron('0 9 * * *'))).to be_nil
      short_minutes_cron = Struct.new(:hours, :monthdays, :months, :weekdays, :minutes).new(nil, nil, nil, nil, [0])
      expect(described_class.send(:every_minute_interval_phrase, short_minutes_cron)).to be_nil
      expect(described_class.send(:derive_interval, [0, 0])).to be_nil
      expect(described_class.send(:derive_interval, [0, 59])).to be_nil
      expect(described_class.send(:at_time_weekday_phrase, Fugit.parse_cron('*/5 * * * 1'))).to be_nil
      invalid_weekday_cron = Struct.new(:minutes, :hours, :weekdays, :monthdays, :months).new([0], [9], [1, 2], nil, nil)
      expect(described_class.send(:at_time_weekday_phrase, invalid_weekday_cron)).to be_nil
      expect(described_class.send(:at_time_daily_phrase, Fugit.parse_cron('*/5 * * * *'))).to be_nil
      expect(described_class.send(:extract_weekday, [1])).to eq(1)
      expect(described_class.send(:extract_weekday, [[nil]])).to be_nil
      expect(described_class.send(:humanize_cron, Fugit.parse_cron('0 0 * * *'))).to eq('Daily')
      expect(described_class.send(:every_minute_interval_phrase, Fugit.parse_cron('*/15 * * * *'))).to eq('Every 15 minutes')

      stub_const('Kaal::CronHumanizer::MACRO_PHRASES', Kaal::CronHumanizer::MACRO_PHRASES.except('@yearly'))
      expect(described_class.send(:humanize_macro, '@yearly')).to eq('Cron: @yearly')

      broken_value = Object.new
      broken_value.define_singleton_method(:to_s) { raise 'boom' }
      expect { described_class.to_human(broken_value) }.to raise_error(ArgumentError, /Invalid cron expression/)
    end
  end

  describe Kaal::IdempotencyKeyGenerator do
    let(:configuration) { Kaal::Configuration.new }
    let(:fire_time) { Time.utc(2026, 1, 1, 0, 0, 0) }

    it 'uses the configured namespace' do
      configuration.namespace = 'ops'

      expect(described_class.call('job:key', fire_time, configuration: configuration)).to eq('ops-job:key-1767225600')
    end

    it 'falls back to kaal for blank namespaces' do
      configuration.namespace = nil

      expect(described_class.call('job:key', fire_time, configuration: configuration)).to eq('kaal-job:key-1767225600')
    end
  end

  describe Kaal::Support::HashTools do
    it 'deep duplicates nested structures' do
      source = { a: ['x', { b: 'y' }], proc: -> {} }

      copy = described_class.deep_dup(source)
      copy[:a][1][:b] = 'z'

      expect(source[:a][1][:b]).to eq('y')
    end

    it 'stringifies, symbolizes, and deep merges nested hashes' do
      expect(described_class.stringify_keys(a: { b: 1 })).to eq('a' => { 'b' => 1 })
      expect(described_class.symbolize_keys('a' => { 'b' => 1 })).to eq(a: { b: 1 })
      expect(described_class.deep_merge({ 'a' => { 'b' => 1 } }, { 'a' => { 'c' => 2 } })).to eq('a' => { 'b' => 1, 'c' => 2 })
    end

    it 'constantizes names and detects duplicable values' do
      expect(described_class.constantize('String')).to eq(String)
      expect(described_class.duplicable?('x')).to be(true)
      expect(described_class.duplicable?(nil)).to be(false)
      expect(described_class.duplicable?(1)).to be(false)
      expect(described_class.duplicable?(:symbol)).to be(false)
      expect(described_class.duplicable?(method(:puts))).to be(false)
    end

    it 'deep merges scalar values by duplicating the right side' do
      right_value = +'right'
      merged = described_class.deep_merge({ 'a' => 'left' }, { 'a' => right_value })

      expect(merged).to eq('a' => 'right')
      expect(merged['a']).not_to equal(right_value)
    end
  end
end
