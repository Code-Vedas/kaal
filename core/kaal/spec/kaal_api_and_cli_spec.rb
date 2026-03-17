# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Kaal do
  let(:fire_time) { Time.utc(2026, 1, 1, 0, 0, 0) }

  before do
    described_class.instance_variable_set(:@registration_service, nil)
    I18n.load_path = [File.expand_path('../config/locales/en.yml', __dir__)]
    I18n.backend.load_translations
  end

  it 'exposes version and configuration accessors' do
    expect(Kaal::VERSION).to eq('0.2.1')

    described_class.tick_interval = 7
    described_class.window_lookback = 10
    described_class.window_lookahead = 2
    described_class.lease_ttl = 20
    described_class.namespace = 'ops'
    described_class.backend = Kaal::Backend::MemoryAdapter.new
    described_class.logger = Logger.new(StringIO.new)
    described_class.time_zone = 'UTC'

    expect(described_class.tick_interval).to eq(7)
    expect(described_class.window_lookback).to eq(10)
    expect(described_class.window_lookahead).to eq(2)
    expect(described_class.lease_ttl).to eq(20)
    expect(described_class.namespace).to eq('ops')
    expect(described_class.backend).to be_a(Kaal::Backend::MemoryAdapter)
    expect(described_class.logger).to be_a(Logger)
    expect(described_class.time_zone).to eq('UTC')
  end

  it 'loads scheduler files, manages registries, and delegates to coordinator and helpers' do
    loader = instance_double(Kaal::SchedulerFileLoader, load: [:ok])
    coordinator = instance_double(
      Kaal::Coordinator,
      start!: :thread,
      stop!: true,
      running?: true,
      restart!: :restarted,
      tick!: :ticked
    )
    allow(Kaal::SchedulerFileLoader).to receive(:new).and_return(loader)
    allow(described_class).to receive(:coordinator).and_return(coordinator)

    callback = ->(**) {}
    described_class.register(key: 'job:a', cron: '* * * * *', enqueue: callback)
    described_class.enable(key: 'job:a')
    described_class.disable(key: 'job:a')

    expect(described_class.load_scheduler_file!).to eq([:ok])
    expect(described_class.registered?(key: 'job:a')).to be(true)
    expect(described_class.registered.first.key).to eq('job:a')
    expect(described_class.start!).to eq(:thread)
    expect(described_class.stop!).to be(true)
    expect(described_class.running?).to be(true)
    expect(described_class.restart!).to eq(:restarted)
    expect(described_class.tick!).to eq(:ticked)
    expect(described_class.dispatched?('job:a', fire_time)).to be(false)
    expect(described_class.dispatch_log_registry).to be_nil
    expect(described_class.valid?('* * * * *')).to be(true)
    expect(described_class.simplify('0 0 * * *')).to eq('@daily')
    expect(described_class.lint('* * * * *')).to eq([])
    expect(described_class.to_human('@daily')).to eq('Daily')
    expect(described_class.validate).to eq([])
    expect(described_class.validate!).to be_a(Kaal::Configuration)

    expect { described_class.with_idempotency('job:a', fire_time) }.to raise_error(ArgumentError)
    yielded_key = nil
    described_class.with_idempotency('job:a', fire_time) { |key| yielded_key = key }
    expect(yielded_key).to include('job:a')

    described_class.unregister(key: 'job:a')
    expect(described_class.registered?(key: 'job:a')).to be(false)
  end

  it 'covers configure without a block and reset branches for memoized helpers' do
    described_class.configure
    definition_registry = described_class.definition_registry
    definition_registry.upsert_definition(key: 'job:a', cron: '* * * * *', enabled: true, source: 'code', metadata: {})
    described_class.instance_variable_set(:@definition_registry, definition_registry)
    described_class.reset_registry!
    expect(described_class.definition_registry.all_definitions).to eq([])

    coordinator = instance_double(Kaal::Coordinator, running?: false)
    described_class.instance_variable_set(:@coordinator, coordinator)
    expect(described_class.reset_coordinator!).to be_a(Kaal::Coordinator)
  end

  it 'resets configuration, registry, and coordinator state' do
    described_class.register(key: 'job:a', cron: '* * * * *', enqueue: ->(**) {})
    coordinator = instance_double(Kaal::Coordinator, running?: true, stop!: true)
    described_class.instance_variable_set(:@coordinator, coordinator)

    expect(described_class.reset_coordinator!).to be_a(Kaal::Coordinator)
    described_class.reset_registry!
    described_class.reset_configuration!
    expect(described_class.configuration).to be_a(Kaal::Configuration)
    expect(described_class.registry).to be_a(Kaal::Registry)
  end

  it 'raises if a running coordinator cannot be stopped during reset' do
    coordinator = instance_double(Kaal::Coordinator, running?: true, stop!: false)
    described_class.instance_variable_set(:@coordinator, coordinator)

    expect { described_class.reset_coordinator! }.to raise_error(RuntimeError, /Failed to stop coordinator thread/)
  end

  it 'rolls definitions back through both private branches' do
    definition_registry = described_class.definition_registry
    definition_registry.upsert_definition(key: 'job:a', cron: '* * * * *', enabled: true, source: 'code', metadata: {})

    described_class.send(:rollback_registered_definition, 'job:a', {
                           key: 'job:a',
                           cron: '*/5 * * * *',
                           enabled: false,
                           source: 'file',
                           metadata: { owner: 'ops' }
                         })
    expect(definition_registry.find_definition('job:a')).to include(cron: '*/5 * * * *', source: 'file')

    described_class.send(:rollback_registered_definition, 'job:missing', nil)
    expect(definition_registry.find_definition('job:missing')).to be_nil
  end

  describe Kaal::CLI do
    let(:shell_output) { StringIO.new }
    let(:shell) { Thor::Shell::Basic.new }
    let(:message_shell) do
      Class.new do
        attr_reader :messages

        def initialize
          @messages = []
        end

        def say(message)
          @messages << message
        end

        def warn(message)
          @messages << message
        end
      end.new
    end

    before do
      allow(shell).to receive(:stdout).and_return(shell_output)
    end

    it 'renders config templates for each backend' do
      cli = described_class.new([], {}, shell:)

      expect(cli.send(:root_path)).to eq(Dir.pwd)
      expect(cli.send(:config_path)).to eq(File.join(Dir.pwd, 'config', 'kaal.rb'))
      expect(cli.send(:scheduler_path)).to eq(File.join(Dir.pwd, 'config', 'scheduler.yml'))
      expect(cli.send(:render_config_template, 'memory')).to include('MemoryAdapter')
      expect(cli.send(:render_config_template, 'redis')).to include('RedisAdapter')
      expect { cli.send(:render_config_template, 'unknown') }.to raise_error(Thor::Error)
      expect(cli.send(:scheduler_template)).to include('example:heartbeat')
    end

    it 'reports status, ticks once, explains crons, and validates next expressions' do
      cli = described_class.new([], {}, shell:)
      allow(cli).to receive(:load_project!)
      allow(Kaal).to receive_messages(
        running?: false,
        registered: [Kaal::Registry::Entry.new(key: 'job:a', cron: '* * * * *', enqueue: ->(**) {})],
        tick!: true,
        to_human: 'Daily'
      )
      cli.status
      cli.tick
      cli.explain('@daily')

      expect(shell_output.string).to include('Kaal v0.2.1', 'Registered jobs: 1', 'Kaal tick completed', 'Daily')
      expect { cli.invoke(:next, ['bad cron']) }.to raise_error(Thor::Error, /Invalid cron expression/)
    end

    it 'starts in foreground and handles repeated shutdown signals' do
      thread = instance_double(Thread, join: true)
      signal_state = { graceful_shutdown_started: false, shutdown_complete: false, force_exit_requested: false }
      cli = described_class.new([], {}, shell:)
      allow(cli).to receive(:load_project!)
      allow(described_class).to receive(:install_foreground_signal_handlers).and_return('TERM' => 'DEFAULT')
      allow(Kaal).to receive_messages(start!: thread, stop!: true)
      allow(Signal).to receive(:trap)

      cli.start
      expect(shell_output.string).to include('Kaal scheduler started in foreground')

      described_class.shutdown_scheduler(signal: 'TERM', signal_state:, shell: message_shell)
      expect(signal_state[:shutdown_complete]).to be(true)

      signal_state = { graceful_shutdown_started: true, shutdown_complete: false, force_exit_requested: false }
      allow(Thread.main).to receive(:raise)
      described_class.shutdown_scheduler(signal: 'TERM', signal_state:, shell: message_shell)
      expect(signal_state[:force_exit_requested]).to be(true)

      allow(Kaal).to receive_messages(start!: thread, stop!: false)
      signal_state = { graceful_shutdown_started: false, shutdown_complete: false, force_exit_requested: false }
      described_class.shutdown_scheduler(signal: 'TERM', signal_state:, shell: message_shell)
      expect(message_shell.messages).to include('Kaal scheduler stop timed out; send TERM/INT again to force exit')
    end

    it 'restores signal handlers and exits on failure' do
      allow(Signal).to receive(:trap).and_raise(StandardError)

      described_class.restore_signal_handlers('TERM' => 'DEFAULT')
      expect(described_class.exit_on_failure?).to be(true)
    end

    it 'handles non-forced interrupts and already-running starts' do
      cli = described_class.new([], {}, shell:)
      allow(cli).to receive(:load_project!)
      allow(described_class).to receive(:install_foreground_signal_handlers).and_return({})
      allow(described_class).to receive(:restore_signal_handlers)
      allow(described_class).to receive(:shutdown_scheduler)
      allow(Kaal).to receive(:start!).and_raise(Interrupt)

      cli.start
      expect(described_class).to have_received(:shutdown_scheduler)

      allow(Kaal).to receive(:start!).and_return(nil)
      expect { cli.start }.to raise_error(Thor::Error, /already running/)
    end

    it 'loads project files and installs foreground handlers' do
      root = Dir.mktmpdir
      cli = described_class.new([], { root: root, config: File.join(root, 'config', 'custom.rb') }, shell:)
      FileUtils.mkdir_p(File.join(root, 'config'))
      File.write(File.join(root, 'config', 'custom.rb'), "Kaal.configure { |config| config.tick_interval = 9 }\n")
      File.write(File.join(root, 'config', 'scheduler.yml'), "defaults:\n  jobs: []\n")
      allow(Kaal).to receive(:load_scheduler_file!).and_return([])
      allow(Kaal::SignalHandlerInstaller).to receive(:new).and_return(
        instance_double(Kaal::SignalHandlerInstaller, install: { 'TERM' => 'DEFAULT' })
      )

      cli.send(:load_project!)
      expect(Kaal.tick_interval).to eq(9)
      expect(described_class.install_foreground_signal_handlers({})).to eq({ 'TERM' => 'DEFAULT' })

      test_path = File.join(root, 'tmp.txt')
      described_class.write_file(test_path, 'one')
      described_class.write_file(test_path, 'two')
      expect(File.read(test_path)).to eq('one')
    ensure
      FileUtils.remove_entry(root)
    end

    it 'executes the installed foreground signal callback and ignores completed shutdowns' do
      callback = nil
      installer = instance_double(Kaal::SignalHandlerInstaller)
      allow(Kaal::SignalHandlerInstaller).to receive(:new).and_return(installer)
      allow(installer).to receive(:install) do |&block|
        callback = block
        { 'TERM' => 'DEFAULT' }
      end
      allow(described_class).to receive(:shutdown_scheduler)

      described_class.install_foreground_signal_handlers({})
      callback.call('TERM', 'DEFAULT')
      expect(described_class).to have_received(:shutdown_scheduler).with(
        signal: 'TERM',
        signal_state: {},
        previous_handler: 'DEFAULT'
      )

      signal_state = { graceful_shutdown_started: false, shutdown_complete: true, force_exit_requested: false }
      expect(described_class.shutdown_scheduler(signal: 'TERM', signal_state:, shell: message_shell)).to be_nil
    end

    it 'raises when start is interrupted after force-exit request' do
      cli = described_class.new([], {}, shell:)
      allow(cli).to receive(:load_project!)
      allow(described_class).to receive(:install_foreground_signal_handlers) do |signal_state|
        signal_state[:force_exit_requested] = true
        {}
      end
      allow(described_class).to receive(:restore_signal_handlers)
      allow(Kaal).to receive(:start!).and_raise(Interrupt)

      expect { cli.start }.to raise_error(Thor::Error, /forced exit requested/)
    end

    it 'covers init without migrations and completed shutdown return' do
      root = Dir.mktmpdir
      cli = described_class.new([], { root: root }, shell:)
      allow(cli).to receive(:say)
      cli.invoke(:init, [], backend: 'memory')

      expect(File.exist?(File.join(root, 'db', 'migrate'))).to be(false)

      signal_state = { graceful_shutdown_started: false, shutdown_complete: true, force_exit_requested: false }
      expect(described_class.shutdown_scheduler(signal: 'TERM', signal_state:, shell: message_shell)).to be_nil
    ensure
      FileUtils.remove_entry(root)
    end

    it 'loads a project without a scheduler file' do
      root = Dir.mktmpdir
      cli = described_class.new([], { root: root }, shell:)
      FileUtils.mkdir_p(File.join(root, 'config'))
      File.write(File.join(root, 'config', 'kaal.rb'), "Kaal.configure { |config| config.tick_interval = 9 }\n")
      allow(Kaal).to receive(:load_scheduler_file!)

      cli.send(:load_project!)

      expect(Kaal).not_to have_received(:load_scheduler_file!)
    ensure
      FileUtils.remove_entry(root)
    end
  end
end
