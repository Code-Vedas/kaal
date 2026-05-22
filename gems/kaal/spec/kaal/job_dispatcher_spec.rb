# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'spec_helper'

RSpec.describe Kaal::JobDispatcher do
  before do
    Kaal.configuration.delayed_job_allowed_class_prefixes = []

    stub_const('DispatcherLaterJob', Class.new do
      class << self
        attr_reader :calls
      end

      @calls = []

      def self.perform_later(*args)
        @calls << args
      end
    end)

    stub_const('DispatcherPerformJob', Class.new do
      class << self
        attr_reader :calls
      end

      @calls = []

      def self.perform(*args)
        @calls << args
      end
    end)

    stub_const('DispatcherQueueJob', Class.new do
      class << self
        attr_reader :queues, :calls
      end

      @queues = []
      @calls = []

      def self.set(queue:)
        @queues << queue
        job_class = self
        Class.new do
          define_singleton_method(:perform_later) do |*args|
            job_class.calls << args
          end
        end
      end
    end)

    stub_const('DispatcherBrokenQueueJob', Class.new do
      def self.perform_later(*) = nil
    end)
  end

  it 'resolves constant and module job classes' do
    expect(described_class.resolve_job_class(job_class_name: 'DispatcherLaterJob', key: 'job:a')).to eq(DispatcherLaterJob)
    expect(described_class.resolve_job_class(job_class_name: DispatcherLaterJob, key: 'job:a')).to eq(DispatcherLaterJob)
    expect(described_class.normalize_job_class_name(DispatcherLaterJob)).to eq('DispatcherLaterJob')
    expect(described_class.normalize_job_class_name(' DispatcherLaterJob ')).to eq('DispatcherLaterJob')
    expect(described_class.normalized_job_class_name(job_class_name: ' DispatcherLaterJob ', key: 'job:a')).to eq('DispatcherLaterJob')
  end

  it 'dispatches through queue, perform_later, and perform branches' do
    described_class.dispatch(job_class: DispatcherQueueJob, queue: 'low', args: [1])
    described_class.dispatch(job_class: DispatcherLaterJob, queue: nil, args: [2])
    described_class.dispatch(job_class: DispatcherPerformJob, queue: nil, args: [3])

    expect(DispatcherQueueJob.queues).to eq(['low'])
    expect(DispatcherQueueJob.calls).to eq([[1]])
    expect(DispatcherLaterJob.calls).to eq([[2]])
    expect(DispatcherPerformJob.calls).to eq([[3]])
  end

  it 'validates dispatch interfaces and reports unsupported classes' do
    expect(described_class.active_job_dispatch?(DispatcherQueueJob, 'low')).to be(true)
    expect(described_class.active_job_dispatch?(DispatcherLaterJob, nil)).to be(true)
    expect(described_class.active_job_dispatch?(DispatcherPerformJob, nil)).to be(false)

    expect do
      described_class.resolve_job_class(job_class_name: ' ', key: 'job:a')
    end.to raise_error(Kaal::SchedulerConfigError, /Job class cannot be blank/)

    expect do
      described_class.resolve_job_class(job_class_name: 'MissingDispatcherJob', key: 'job:a')
    end.to raise_error(Kaal::SchedulerConfigError, /Unknown job_class/)

    expect do
      described_class.resolve_job_class(job_class_name: DispatcherBrokenQueueJob, key: 'job:a', queue: 'low')
    end.to raise_error(Kaal::SchedulerConfigError, /must respond to \.perform/)

    expect do
      described_class.dispatch(job_class: DispatcherBrokenQueueJob, queue: 'low', args: [])
    end.to raise_error(Kaal::SchedulerConfigError, /must respond to \.set/)

    expect do
      described_class.dispatch(job_class: Class.new, queue: nil, args: [])
    end.to raise_error(Kaal::SchedulerConfigError, /must respond to \.perform/)
  end

  it 'rejects job classes outside the configured delayed-job allow-list' do
    Kaal.configuration.delayed_job_allowed_class_prefixes = ['Allowed::']

    expect do
      described_class.normalized_job_class_name(job_class_name: 'DispatcherLaterJob', key: 'job:a')
    end.to raise_error(Kaal::SchedulerConfigError, /not allowed/)
  end
end
