# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'spec_helper'
require 'rake'
require 'stringio'

RSpec.describe RailsCron::RakeTasks do
  let(:rake) { Rake::Application.new }

  before do
    Rake.application = rake
    rake.define_task(Rake::Task, :environment)
    described_class.install(rake)
  end

  after do
    Rake.application = nil
  end

  def task(name)
    rake[name]
  end

  describe 'rails_cron:tick' do
    it 'runs a single tick and prints success' do
      allow(RailsCron).to receive(:tick!)

      expect { task('rails_cron:tick').invoke }.to output(/tick completed/).to_stdout
      expect(RailsCron).to have_received(:tick!)
    end

    it 'aborts on errors' do
      allow(RailsCron).to receive(:tick!).and_raise(StandardError, 'boom')

      expect { task('rails_cron:tick').invoke }.to raise_error(SystemExit)
    end
  end

  describe 'rails_cron:status' do
    it 'prints scheduler state and registered jobs' do
      entry = instance_double(RailsCron::Registry::Entry, key: 'reports:daily', cron: '0 9 * * *')
      allow(RailsCron).to receive_messages(
        running?: false,
        tick_interval: 5,
        window_lookback: 120,
        window_lookahead: 0,
        lease_ttl: 125,
        namespace: 'railscron',
        registered: [entry]
      )

      output = capture_stdout { task('rails_cron:status').invoke }
      expect(output).to include('RailsCron v')
      expect(output).to include('Running: false')
      expect(output).to include('Registered jobs: 1')
      expect(output).to include('reports:daily')
    end

    it 'aborts on errors' do
      allow(RailsCron).to receive(:running?).and_raise(StandardError, 'boom')

      expect { task('rails_cron:status').invoke }.to raise_error(SystemExit)
    end
  end

  describe 'rails_cron:explain' do
    it 'prints humanized cron text' do
      allow(RailsCron).to receive(:to_human).with('*/5 * * * *').and_return('Every 5 minutes')

      expect { task('rails_cron:explain').invoke('*/5 * * * *') }.to output("Every 5 minutes\n").to_stdout
    end

    it 'aborts when expression argument is missing' do
      expect { task('rails_cron:explain').invoke }.to raise_error(SystemExit)
    end

    it 'aborts with invalid cron expressions' do
      allow(RailsCron).to receive(:to_human).and_raise(ArgumentError, 'Invalid cron expression')

      expect { task('rails_cron:explain').invoke('bad') }.to raise_error(SystemExit)
    end
  end

  describe 'rails_cron:start' do
    it 'starts scheduler in foreground and joins thread' do
      thread = instance_double(Thread, join: nil)
      allow(RailsCron).to receive(:start!).and_return(thread)

      expect { task('rails_cron:start').invoke }.to output(/started in foreground/).to_stdout
      expect(thread).to have_received(:join)
    end

    it 'aborts when scheduler is already running' do
      allow(RailsCron).to receive(:start!).and_return(nil)

      expect { task('rails_cron:start').invoke }.to raise_error(SystemExit)
    end

    it 'handles interrupts by stopping scheduler' do
      thread = instance_double(Thread)
      allow(thread).to receive(:join).and_raise(Interrupt)
      allow(RailsCron).to receive(:start!).and_return(thread)
      allow(RailsCron).to receive(:stop!).with(timeout: 30)

      expect { task('rails_cron:start').invoke }.to output(/scheduler stopped/).to_stdout
      expect(RailsCron).to have_received(:stop!).with(timeout: 30)
    end

    it 'aborts when start raises unexpected errors' do
      allow(RailsCron).to receive(:start!).and_raise(StandardError, 'boom')

      expect { task('rails_cron:start').invoke }.to raise_error(SystemExit)
    end
  end

  def capture_stdout
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original_stdout
  end
end
