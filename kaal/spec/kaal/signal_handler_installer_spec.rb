# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'spec_helper'

RSpec.describe Kaal::SignalHandlerInstaller do
  subject(:installer) { described_class.new(signal_module: signal_module) }

  let(:signal_module) { class_double(Signal) }

  it 'installs handlers for each signal and returns previous handlers' do
    installed_blocks = {}
    trap_count = Hash.new(0)

    allow(signal_module).to receive(:trap) do |signal, handler = nil, &block|
      trap_count[signal] += 1
      case [signal, trap_count[signal], handler]
      when ['TERM', 1, 'IGNORE']
        :term_previous
      when ['INT', 1, 'IGNORE']
        :int_previous
      when ['TERM', 2, :term_previous], ['INT', 2, :int_previous]
        nil
      else
        installed_blocks[signal] = block if block
        nil
      end
    end

    previous_handlers = installer.install { |_signal, _previous_handler| nil }

    expect(previous_handlers).to eq('TERM' => :term_previous, 'INT' => :int_previous)
    expect(installed_blocks.keys).to contain_exactly('TERM', 'INT')
  end

  it 'does not restore ignored handlers before installing the new trap' do
    calls = []
    allow(signal_module).to receive(:trap) do |signal, handler = nil, &block|
      calls << [signal, handler, block.nil?]
      handler == 'IGNORE' ? 'IGNORE' : nil
    end

    installer.install(signals: ['TERM']) { |_signal, _previous_handler| nil }

    expect(calls).to eq(
      [
        ['TERM', 'IGNORE', true],
        ['TERM', nil, false]
      ]
    )
  end

  it 'yields the preserved previous handler into the installed block' do
    installed_block = nil
    allow(signal_module).to receive(:trap) do |_signal, handler = nil, &block|
      if handler == 'IGNORE'
        :previous_handler
      else
        installed_block = block
        nil
      end
    end

    yielded = []
    installer.install(signals: ['TERM']) do |signal, previous_handler|
      yielded << [signal, previous_handler]
    end
    installed_block.call

    expect(yielded).to eq([['TERM', :previous_handler]])
  end
end
