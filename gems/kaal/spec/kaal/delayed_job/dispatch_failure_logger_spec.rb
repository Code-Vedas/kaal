# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'spec_helper'

RSpec.describe Kaal::DelayedJob::DispatchFailureLogger do
  let(:job) do
    {
      job_id: 'job:a',
      job_class: 'ExampleJob',
      queue: 'low',
      run_at: Time.utc(2026, 1, 1)
    }
  end
  let(:error) { RuntimeError.new('boom') }

  it 'logs through fatal when available' do
    logger = instance_double(Logger)
    allow(logger).to receive(:respond_to?).with(:fatal).and_return(true)
    allow(logger).to receive(:fatal)

    described_class.log_claimed_dispatch_failure(logger:, job:, error:)

    expect(logger).to have_received(:fatal).with(include('job was already claimed and will not be retried'))
  end

  it 'falls back to error and tolerates a nil logger' do
    logger = instance_double(Logger)
    allow(logger).to receive(:respond_to?).with(:fatal).and_return(false)
    allow(logger).to receive(:error)

    described_class.log_claimed_dispatch_failure(logger:, job:, error:)
    described_class.log_claimed_dispatch_failure(logger: nil, job:, error:)

    expect(logger).to have_received(:error).with(include('Delayed job job:a dispatch failed after claim'))
  end
end
