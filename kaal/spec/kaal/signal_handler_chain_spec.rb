# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'spec_helper'

RSpec.describe Kaal::SignalHandlerChain do
  let(:logger) { instance_spy(Logger) }

  it 'calls callable handlers with no arguments when arity is zero' do
    invoked = []
    handler = proc { invoked << :called }

    described_class.new(signal: 'TERM', previous_handler: handler, logger: logger).call('TERM')

    expect(invoked).to eq([:called])
  end

  it 'passes through arguments to callable handlers when arity is positive' do
    invoked = []
    handler = proc { |signal| invoked << signal }

    described_class.new(signal: 'TERM', previous_handler: handler, logger: logger).call('TERM')

    expect(invoked).to eq(['TERM'])
  end

  it 'passes through all arguments to variadic handlers' do
    invoked = []
    handler = proc { |*args| invoked << args }

    described_class.new(signal: 'TERM', previous_handler: handler, logger: logger).call('TERM', 15)

    expect(invoked).to eq([['TERM', 15]])
  end

  it 'logs debug output for string command handlers' do
    described_class.new(signal: 'TERM', previous_handler: 'some_command', logger: logger).call

    expect(logger).to have_received(:debug).with('Previous TERM handler was a command: some_command')
  end

  it 'ignores reserved string handlers' do
    described_class.new(signal: 'TERM', previous_handler: 'DEFAULT', logger: logger).call
    described_class.new(signal: 'TERM', previous_handler: 'IGNORE', logger: logger).call

    expect(logger).not_to have_received(:debug)
  end

  it 'ignores nil handlers' do
    expect { described_class.new(signal: 'TERM', previous_handler: nil, logger: logger).call }.not_to raise_error
  end
end
