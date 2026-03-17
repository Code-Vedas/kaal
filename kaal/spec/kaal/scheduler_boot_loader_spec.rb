# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

require 'spec_helper'

RSpec.describe Kaal::SchedulerBootLoader do
  subject(:loader) do
    described_class.new(
      configuration_provider: -> { configuration },
      logger: logger,
      runtime_context: runtime_context,
      load_scheduler_file: load_scheduler_file
    )
  end

  let(:configuration) { Kaal::Configuration.new }
  let(:logger) { instance_spy(Logger) }
  let(:runtime_context) { instance_double(Kaal::RuntimeContext) }
  let(:load_scheduler_file) { instance_spy(Proc) }

  it 'loads immediately when missing-file policy is error' do
    configuration.scheduler_missing_file_policy = :error
    configuration.scheduler_config_path = 'config/scheduler.yml'

    loader.load_on_boot!

    expect(load_scheduler_file).to have_received(:call)
  end

  it 'loads when the scheduler file exists' do
    configuration.scheduler_missing_file_policy = :warn
    configuration.scheduler_config_path = 'config/scheduler.yml'
    allow(runtime_context).to receive(:resolve_path).with('config/scheduler.yml').and_return('/app/config/scheduler.yml')
    allow(File).to receive(:exist?).with('/app/config/scheduler.yml').and_return(true)

    loader.load_on_boot!

    expect(load_scheduler_file).to have_received(:call)
  end

  it 'warns and skips loading when the scheduler file is missing' do
    configuration.scheduler_missing_file_policy = :warn
    configuration.scheduler_config_path = 'config/scheduler.yml'
    allow(runtime_context).to receive(:resolve_path).with('config/scheduler.yml').and_return('/app/config/scheduler.yml')
    allow(File).to receive(:exist?).with('/app/config/scheduler.yml').and_return(false)

    loader.load_on_boot!

    expect(load_scheduler_file).not_to have_received(:call)
    expect(logger).to have_received(:warn).with('Scheduler file not found at /app/config/scheduler.yml')
  end

  it 'skips missing-file checks when the scheduler path is blank' do
    configuration.scheduler_missing_file_policy = :warn
    configuration.scheduler_config_path = '   '

    loader.load_on_boot!

    expect(load_scheduler_file).not_to have_received(:call)
  end

  it 'exposes a non-bang boot loader that delegates to load_on_boot!' do
    configuration.scheduler_missing_file_policy = :error
    configuration.scheduler_config_path = 'config/scheduler.yml'

    loader.load_on_boot

    expect(load_scheduler_file).to have_received(:call)
  end

  it 'logs and skips boot loading when configuration lookup raises NameError' do
    failing_loader = described_class.new(
      configuration_provider: -> { raise NameError, 'uninitialized constant MissingConfig' },
      logger: logger,
      runtime_context: runtime_context,
      load_scheduler_file: load_scheduler_file
    )

    failing_loader.load_on_boot!

    expect(load_scheduler_file).not_to have_received(:call)
    expect(logger).to have_received(:debug).with(/Skipping scheduler file boot load/)
  end

  it 'does not crash when logger is nil and configuration lookup raises NameError' do
    failing_loader = described_class.new(
      configuration_provider: -> { raise NameError, 'uninitialized constant MissingConfig' },
      logger: nil,
      runtime_context: runtime_context,
      load_scheduler_file: load_scheduler_file
    )

    expect { failing_loader.load_on_boot! }.not_to raise_error
  end
end
