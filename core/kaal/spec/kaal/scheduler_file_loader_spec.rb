# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'spec_helper'

RSpec.describe Kaal::SchedulerFileLoader do
  let(:root) { Dir.mktmpdir }
  let(:runtime_context) { Kaal::RuntimeContext.new(root_path: root, environment_name: 'development') }
  let(:job_calls) { [] }
  let(:job_class) do
    calls = job_calls
    Class.new do
      define_singleton_method(:perform) do |*args, **kwargs|
        calls << { args: args, kwargs: kwargs }
      end
    end
  end

  before do
    stub_const('ExampleSchedulerJob', job_class)
    FileUtils.mkdir_p(File.join(root, 'config'))
    File.write(
      File.join(root, 'config', 'scheduler.yml'),
      <<~YAML
        defaults:
          jobs:
            - key: "example:heartbeat"
              cron: "*/5 * * * *"
              job_class: "ExampleSchedulerJob"
              enabled: true
              args:
                - "{{fire_time.iso8601}}"
              kwargs:
                idempotency_key: "{{idempotency_key}}"
      YAML
    )
  end

  after do
    FileUtils.remove_entry(root)
  end

  it 'loads scheduler jobs and builds executable callbacks' do
    jobs = described_class.new(
      configuration: Kaal.configuration,
      definition_registry: Kaal.definition_registry,
      registry: Kaal.registry,
      logger: Logger.new(StringIO.new),
      runtime_context: runtime_context
    ).load

    expect(jobs.map { |job| job[:key] }).to eq(['example:heartbeat'])

    callback = Kaal.registry.find('example:heartbeat').enqueue
    callback.call(fire_time: Time.utc(2026, 1, 1, 0, 0, 0), idempotency_key: 'abc123')

    expect(job_calls).to eq([
                              { args: ['2026-01-01T00:00:00Z'], kwargs: { idempotency_key: 'abc123' } }
                            ])
  end

  it 'handles missing scheduler files according to policy' do
    FileUtils.rm_f(File.join(root, 'config', 'scheduler.yml'))

    loader = described_class.new(
      configuration: Kaal.configuration,
      definition_registry: Kaal.definition_registry,
      registry: Kaal.registry,
      logger: Logger.new(StringIO.new),
      runtime_context: runtime_context
    )

    expect(loader.load).to eq([])

    Kaal.configure { |config| config.scheduler_missing_file_policy = :error }
    expect { loader.load }.to raise_error(Kaal::SchedulerConfigError, /Scheduler file not found/)
  end

  it 'validates scheduler payloads, placeholders, and rollback behavior' do
    loader = described_class.new(
      configuration: Kaal.configuration,
      definition_registry: Kaal.definition_registry,
      registry: Kaal.registry,
      logger: Logger.new(StringIO.new),
      runtime_context: runtime_context
    )
    payload_loader = loader.send(:payload_loader)

    expect(payload_loader.extract_jobs('defaults' => { 'jobs' => [] }, 'development' => { 'jobs' => [] })).to eq([])
    expect do
      payload_loader.extract_jobs('defaults' => { 'jobs' => 'bad' }, 'development' => { 'jobs' => [] })
    end.to raise_error(Kaal::SchedulerConfigError)
    expect do
      payload_loader.validate_unique_keys([{ 'key' => 'dup' }, { 'key' => 'dup' }])
    end.to raise_error(Kaal::SchedulerConfigError, /Duplicate job keys/)

    expect do
      loader.send(:normalize_job, { 'key' => 'bad', 'cron' => '* * * * *', 'job_class' => 'ExampleSchedulerJob', 'kwargs' => [] })
    end.to raise_error(Kaal::SchedulerConfigError, /kwargs must be a mapping/)

    expect do
      loader.send(:normalize_job, { 'key' => 'bad', 'cron' => '* * * * *', 'job_class' => 'ExampleSchedulerJob', 'args' => ['{{unknown}}'] })
    end.to raise_error(Kaal::SchedulerConfigError, /Unknown placeholder/)

    expect(loader.send(:extract_job_options, { 'args' => [], 'kwargs' => {}, 'metadata' => {} }, key: 'job')).to include(enabled: true)
    expect(loader.send(:resolve_job_class, job_class_name: 'ExampleSchedulerJob', key: 'job')).to eq(ExampleSchedulerJob)
    expect(
      loader.send(
        :build_callback,
        key: 'job',
        job_class_name: 'ExampleSchedulerJob',
        queue: nil,
        args_template: [],
        kwargs_template: {}
      )
    ).to be_a(Proc)
    expect(loader.send(:helper_bundle)).to be_a(Kaal::SchedulerFileLoader::HelperBundle)
  end

  it 'applies scheduler jobs across perform methods and conflict policies' do
    perform_later_calls = []
    set_calls = []
    simple_job = Class.new do
      define_singleton_method(:perform_later) { |*args, **kwargs| perform_later_calls << [args, kwargs] }
    end
    queue_job = Class.new do
      define_singleton_method(:set) do |queue:|
        set_calls << queue
        Class.new do
          define_singleton_method(:perform_later) { |*args, **kwargs| [args, kwargs] }
        end
      end
    end
    stub_const('ExampleLaterJob', simple_job)
    stub_const('ExampleQueueJob', queue_job)

    loader = described_class.new(
      configuration: Kaal.configuration,
      definition_registry: Kaal.definition_registry,
      registry: Kaal.registry,
      logger: Logger.new(StringIO.new),
      runtime_context: runtime_context
    )
    applier = loader.send(:job_applier)

    applier.apply(
      key: 'later',
      cron: '* * * * *',
      job_class_name: 'ExampleLaterJob',
      queue: nil,
      args: ['{{key}}'],
      kwargs: {},
      enabled: true,
      metadata: {}
    )
    Kaal.registry.find('later').enqueue.call(fire_time: Time.utc(2026, 1, 1), idempotency_key: 'abc')
    expect(perform_later_calls).not_to be_empty

    applier.apply(
      key: 'queue',
      cron: '* * * * *',
      job_class_name: 'ExampleQueueJob',
      queue: 'low',
      args: [],
      kwargs: {},
      enabled: true,
      metadata: {}
    )
    Kaal.registry.find('queue').enqueue.call(fire_time: Time.utc(2026, 1, 1), idempotency_key: 'abc')
    expect(set_calls).to eq(['low'])

    Kaal.definition_registry.upsert_definition(key: 'conflict', cron: '* * * * *', enabled: true, source: 'code', metadata: {})
    Kaal.configure { |config| config.scheduler_conflict_policy = :code_wins }
    expect(applier.conflict?(key: 'conflict', existing_definition: Kaal.definition_registry.find_definition('conflict'))).to be(true)
  end

  it 'covers job applier rollback and callback error paths' do
    loader = described_class.new(
      configuration: Kaal.configuration,
      definition_registry: Kaal.definition_registry,
      registry: Kaal.registry,
      logger: Logger.new(StringIO.new),
      runtime_context: runtime_context
    )
    applier = loader.send(:job_applier)

    existing_entry = Kaal.registry.upsert(key: 'restore', cron: '* * * * *', enqueue: ->(**) {})
    Kaal.definition_registry.upsert_definition(key: 'restore', cron: '* * * * *', enabled: true, source: 'code', metadata: {})
    applier.rollback_job(key: 'restore', existing_definition: Kaal.definition_registry.find_definition('restore'), existing_registry_entry: existing_entry)
    applier.rollback_job(key: 'missing', existing_definition: nil, existing_registry_entry: nil)
    applier.rollback_jobs([{ key: 'missing', existing_definition: nil, existing_registry_entry: nil }])

    Kaal.configure { |config| config.scheduler_conflict_policy = :error }
    expect do
      applier.conflict?(key: 'restore', existing_definition: { source: 'code' })
    end.to raise_error(Kaal::SchedulerConfigError, /Scheduler key conflict/)
    Kaal.configure { |config| config.scheduler_conflict_policy = :file_wins }
    expect(applier.conflict?(key: 'restore', existing_definition: { source: 'code' })).to be(false)
    Kaal.configure { |config| config.scheduler_conflict_policy = :unknown }
    expect do
      applier.conflict?(key: 'restore', existing_definition: { source: 'code' })
    end.to raise_error(Kaal::SchedulerConfigError, /Unsupported/)

    expect do
      applier.resolve_job_class_for(job_class_name: 'MissingJobClass', key: 'missing')
    end.to raise_error(Kaal::SchedulerConfigError, /Unknown job_class/)

    expect do
      applier.send(:validate_keyword_keys, { Object.new => 1 }, 'job')
    end.to raise_error(Kaal::SchedulerConfigError, /Invalid keyword argument key/)

    bad_job = Class.new
    stub_const('BadJobClass', bad_job)
    expect do
      applier.send(:dispatch_job, bad_job, nil, [], {})
    end.to raise_error(Kaal::SchedulerConfigError, /must respond to/)

    expect do
      applier.send(:dispatch_job, bad_job, 'low', [], {})
    end.to raise_error(Kaal::SchedulerConfigError, /must respond to \.set to use queue/)

    expect(loader.send(:stringify_keys, a: { b: 1 })).to eq('a' => { 'b' => 1 })
    expect(loader.send(:symbolize_keys_deep, 'a' => { 'b' => 1 })).to eq(a: { b: 1 })
    expect(loader.send(:resolve_placeholders, '{{key}}', key: 'job')).to eq('job')
    expect(loader.send(:resolve_placeholders, ['{{key}}'], key: 'job')).to eq(['job'])
    expect(loader.send(:resolve_placeholders, '{{key}}-{{key}}', key: 'job')).to eq('job-job')
    expect(loader.send(:resolve_placeholders, { a: '{{key}}' }, key: 'job')).to eq({ a: 'job' })
    expect(loader.send(:resolve_placeholders, 1, key: 'job')).to eq(1)
    expect do
      loader.send(:validate_placeholders, { '{{key}}' => 'x' }, key: 'job')
    end.to raise_error(Kaal::SchedulerConfigError, /not supported in hash keys/)
    expect do
      loader.send(:validate_placeholders, '{{ bad-placeholder }}', key: 'job')
    end.to raise_error(Kaal::SchedulerConfigError, /Malformed placeholder/)
  end

  it 'covers payload loader parsing failures and helper wrapper methods' do
    loader = described_class.new(
      configuration: Kaal.configuration,
      definition_registry: Kaal.definition_registry,
      registry: Kaal.registry,
      logger: Logger.new(StringIO.new),
      runtime_context: runtime_context
    )
    payload_loader = loader.send(:payload_loader)
    File.write(File.join(root, 'config', 'scheduler.yml'), "<%= raise 'erb boom' %>")
    expect do
      payload_loader.send(:parse_yaml, File.join(root, 'config', 'scheduler.yml'))
    end.to raise_error(Kaal::SchedulerConfigError, /Failed to evaluate scheduler ERB/)

    File.write(File.join(root, 'config', 'scheduler.yml'), ":\n")
    expect do
      payload_loader.send(:parse_yaml, File.join(root, 'config', 'scheduler.yml'))
    end.to raise_error(Kaal::SchedulerConfigError, /Failed to parse scheduler YAML/)

    Kaal.configure { |config| config.scheduler_config_path = ' ' }
    expect { payload_loader.send(:scheduler_file_path) }.to raise_error(Kaal::SchedulerConfigError, /cannot be blank/)

    Kaal.configure { |config| config.scheduler_config_path = 'config/scheduler.yml' }
    expect(loader.send(:skip_due_to_conflict?, key: 'job', existing_definition: nil)).to be(false)
    expect(
      loader.send(
        :apply_job,
        key: 'direct',
        cron: '* * * * *',
        job_class_name: 'ExampleSchedulerJob',
        queue: nil,
        args: [],
        kwargs: {},
        enabled: true,
        metadata: {}
      )
    ).to be_a(Hash)
    expect(loader.send(:rollback_applied_jobs, [])).to eq([])
    expect(loader.send(:rollback_applied_job, key: 'direct', existing_definition: nil, existing_registry_entry: nil)).to be_nil
    expect(loader.send(:helper_bundle).stringify_keys(a: 1)).to eq('a' => 1)
    expect(loader.send(:helper_bundle).resolve_placeholders('{{key}}', key: 'job')).to eq('job')
    expect(loader.send(:helper_bundle).validate_placeholders('{{key}}', key: 'job')).to eq(['key'])
    expect(loader.send(:resolve_placeholders, '{{fire_time.unix}}', fire_time: Time.utc(2026, 1, 1))).to eq(1_767_225_600)
    expect(loader.send(:validate_placeholders, 1, key: 'job')).to be_nil
    expect(loader.send(:resolve_placeholders, :value, key: 'job')).to eq(:value)
    expect(loader.send(:validate_placeholders, { 'plain' => 'x' }, key: 'job')).to eq({ 'plain' => 'x' })
    expect(loader.send(:validate_placeholders, { 1 => 'x' }, key: 'job')).to eq({ 1 => 'x' })
  end

  it 'covers loader rescue rollback when apply_job fails' do
    broken_registry = Kaal::Registry.new
    allow(broken_registry).to receive(:upsert).and_raise(StandardError, 'upsert boom')
    failing_loader = described_class.new(
      configuration: Kaal.configuration,
      definition_registry: Kaal.definition_registry,
      registry: broken_registry,
      logger: Logger.new(StringIO.new),
      runtime_context: runtime_context
    )
    expect do
      failing_loader.send(
        :apply_job,
        key: 'f',
        cron: '* * * * *',
        job_class_name: 'ExampleSchedulerJob',
        queue: nil,
        args: [],
        kwargs: {},
        enabled: true,
        metadata: {}
      )
    end.to raise_error(StandardError, 'upsert boom')
  end

  it 'covers the skipped apply-job branch during load' do
    loader = described_class.new(
      configuration: Kaal.configuration,
      definition_registry: Kaal.definition_registry,
      registry: Kaal.registry,
      logger: Logger.new(StringIO.new),
      runtime_context: runtime_context
    )
    allow(loader.send(:payload_loader)).to receive(:load).and_return([File.join(root, 'config', 'scheduler.yml'), {}])
    allow(loader).to receive_messages(
      extract_jobs: [{ 'key' => 'job:a', 'cron' => '* * * * *', 'job_class' => 'ExampleSchedulerJob' }],
      validate_unique_keys: nil,
      normalize_job: {
        key: 'job:a',
        cron: '* * * * *',
        job_class_name: 'ExampleSchedulerJob',
        queue: nil,
        args: [],
        kwargs: {},
        enabled: true,
        metadata: {}
      },
      apply_job: nil
    )

    expect(loader.load).to eq([])
  end

  it 'covers payload loader nil-logger and validation edge branches' do
    loader = described_class.new(
      configuration: Kaal.configuration,
      definition_registry: Kaal.definition_registry,
      registry: Kaal.registry,
      logger: nil,
      runtime_context: runtime_context
    )
    payload_loader = loader.send(:payload_loader)

    expect(payload_loader.handle_missing_file('/tmp/missing.yml')).to eq([])
    expect do
      payload_loader.extract_jobs('defaults' => { 'jobs' => [] }, 'development' => { 'jobs' => 'bad' })
    end.to raise_error(Kaal::SchedulerConfigError, /development\.jobs/)
    expect do
      payload_loader.validate_unique_keys([[]])
    end.to raise_error(Kaal::SchedulerConfigError, /Each jobs entry must be a mapping/)

    scheduler_path = File.join(root, 'config', 'scheduler.yml')
    File.write(scheduler_path, "---\n- bad\n")
    expect do
      payload_loader.send(:parse_yaml, scheduler_path)
    end.to raise_error(Kaal::SchedulerConfigError, /root to be a mapping/)

    expect do
      payload_loader.send(:fetch_hash, { 'defaults' => [] }, 'defaults')
    end.to raise_error(Kaal::SchedulerConfigError, /defaults/)
  end

  # rubocop:disable RSpec/ExampleLength
  it 'covers job applier rollback and callback error branches' do
    loader = described_class.new(
      configuration: Kaal.configuration,
      definition_registry: Kaal.definition_registry,
      registry: Kaal.registry,
      logger: Logger.new(StringIO.new),
      runtime_context: runtime_context
    )
    applier = loader.send(:job_applier)

    broken_definition_registry = Kaal::Definition::MemoryEngine.new
    broken_definition_registry.upsert_definition(key: 'broken', cron: '* * * * *', enabled: true, source: 'code', metadata: {})
    allow(broken_definition_registry).to receive(:upsert_definition).and_raise(StandardError, 'definition boom')
    noisy_log = StringIO.new
    noisy_applier = Kaal::SchedulerFileLoader::JobApplier.new(
      configuration: Kaal.configuration,
      definition_registry: broken_definition_registry,
      registry: Kaal.registry,
      logger: Logger.new(noisy_log),
      helper_bundle: loader.send(:helper_bundle)
    )
    noisy_applier.rollback_job(
      key: 'broken',
      existing_definition: { key: 'broken', cron: '* * * * *', enabled: true, source: 'code', metadata: {} },
      existing_registry_entry: nil
    )
    expect(noisy_log.string).to include('Failed to rollback scheduler file application')

    nil_logger_applier = Kaal::SchedulerFileLoader::JobApplier.new(
      configuration: Kaal.configuration,
      definition_registry: broken_definition_registry,
      registry: Kaal.registry,
      logger: nil,
      helper_bundle: loader.send(:helper_bundle)
    )
    expect do
      nil_logger_applier.rollback_job(
        key: 'broken',
        existing_definition: { key: 'broken', cron: '* * * * *', enabled: true, source: 'code', metadata: {} },
        existing_registry_entry: nil
      )
    end.not_to raise_error

    expect do
      applier.send(
        :build_callback,
        {
          key: 'bad',
          queue: nil,
          args: [],
          kwargs: []
        },
        ExampleSchedulerJob
      ).call(fire_time: Time.utc(2026, 1, 1), idempotency_key: 'abc')
    end.to raise_error(Kaal::SchedulerConfigError, /must be a mapping/)
  end

  it 'covers job applier conflict and constantize error branches' do
    loader = described_class.new(
      configuration: Kaal.configuration,
      definition_registry: Kaal.definition_registry,
      registry: Kaal.registry,
      logger: Logger.new(StringIO.new),
      runtime_context: runtime_context
    )
    Kaal.configure { |config| config.scheduler_conflict_policy = :code_wins }
    nil_logger_applier = Kaal::SchedulerFileLoader::JobApplier.new(
      configuration: Kaal.configuration,
      definition_registry: Kaal.definition_registry,
      registry: Kaal.registry,
      logger: nil,
      helper_bundle: loader.send(:helper_bundle)
    )
    expect(nil_logger_applier.conflict?(key: 'restore', existing_definition: { source: 'code' })).to be(true)
    Kaal.definition_registry.upsert_definition(key: 'restore', cron: '* * * * *', enabled: true, source: 'code', metadata: {})
    expect(
      nil_logger_applier.apply(
        key: 'restore',
        cron: '* * * * *',
        job_class_name: 'ExampleSchedulerJob',
        queue: nil,
        args: [],
        kwargs: {},
        enabled: true,
        metadata: {}
      )
    ).to be_nil

    allow(Kaal::Support::HashTools).to receive(:constantize).and_call_original
    allow(Kaal::Support::HashTools).to receive(:constantize).with('MissingJob').and_raise(NameError)
    expect do
      nil_logger_applier.resolve_job_class_for(job_class_name: 'MissingJob', key: 'restore')
    end.to raise_error(Kaal::SchedulerConfigError, /Unknown job_class/)

    expect do
      nil_logger_applier.resolve_job_class_for(job_class_name: '   ', key: 'restore')
    end.to raise_error(Kaal::SchedulerConfigError, /Job class cannot be blank/)

    active_job_class = Class.new do
      def self.perform_later(*) = nil
    end
    stub_const('SchedulerLoaderActiveJobTarget', active_job_class)
    expect(
      nil_logger_applier.send(
        :persisted_metadata,
        { metadata: {}, job_class_name: 'SchedulerLoaderActiveJobTarget', queue: nil, args: [], kwargs: {} },
        active_job_class
      )
    ).to include('execution' => include('target' => 'active_job'))

    unknown_target_class = Class.new
    stub_const('SchedulerLoaderUnknownTarget', unknown_target_class)
    expect(
      nil_logger_applier.send(
        :persisted_metadata,
        { metadata: {}, job_class_name: 'SchedulerLoaderUnknownTarget', queue: nil, args: [], kwargs: {} },
        unknown_target_class
      )
    ).to include('execution' => include('target' => 'ruby'))
  end
  # rubocop:enable RSpec/ExampleLength

  it 'covers direct job normalizer branches' do
    loader = described_class.new(
      configuration: Kaal.configuration,
      definition_registry: Kaal.definition_registry,
      registry: Kaal.registry,
      logger: Logger.new(StringIO.new),
      runtime_context: runtime_context
    )
    normalizer = loader.send(:job_normalizer)

    expect do
      normalizer.call('key' => 'bad', 'cron' => 'not a cron', 'job_class' => 'ExampleSchedulerJob')
    end.to raise_error(Kaal::SchedulerConfigError, /Invalid cron expression/)

    expect do
      normalizer.send(:validate_job_option_types, key: 'bad', args: [], kwargs: { Object.new => 1 }, queue: nil)
    end.to raise_error(Kaal::SchedulerConfigError, /kwargs keys must be strings or symbols/)

    expect do
      normalizer.call('key' => ' ', 'cron' => '* * * * *', 'job_class' => 'ExampleSchedulerJob')
    end.to raise_error(Kaal::SchedulerConfigError, /Job key cannot be blank/)

    expect do
      normalizer.call('key' => 'bad', 'cron' => '* * * * *', 'job_class' => ' ')
    end.to raise_error(Kaal::SchedulerConfigError, /Job class cannot be blank/)

    expect do
      normalizer.call('key' => 'bad', 'cron' => '* * * * *', 'job_class' => 'ExampleSchedulerJob', 'enabled' => 'yes')
    end.to raise_error(Kaal::SchedulerConfigError, /enabled must be a boolean/)

    expect do
      normalizer.call('key' => 'bad', 'cron' => '* * * * *', 'job_class' => 'ExampleSchedulerJob', 'metadata' => [])
    end.to raise_error(Kaal::SchedulerConfigError, /metadata must be a mapping/)

    expect do
      normalizer.send(:validate_job_option_types, key: 'bad', args: 'x', kwargs: {}, queue: nil)
    end.to raise_error(Kaal::SchedulerConfigError, /args must be an array/)

    expect do
      normalizer.send(:validate_job_option_types, key: 'bad', args: [], kwargs: {}, queue: 1)
    end.to raise_error(Kaal::SchedulerConfigError, /queue must be a string/)
  end
end
