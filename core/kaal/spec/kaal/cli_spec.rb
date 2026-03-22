# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.
require 'spec_helper'

RSpec.describe Kaal::CLI do
  let(:root) { Dir.mktmpdir }

  after do
    FileUtils.remove_entry(root)
  end

  it 'initializes a memory project with config files' do
    shell = instance_double(Thor::Shell::Basic, say: nil)
    allow(Thor::Base).to receive(:shell).and_return(class_double(Thor::Shell::Basic, new: shell))
    allow($stdout).to receive(:puts)
    described_class.start(['init', '--backend=memory', "--root=#{root}"])

    expect(File).to exist(File.join(root, 'config', 'kaal.rb'))
    expect(File).to exist(File.join(root, 'config', 'scheduler.yml'))
    expect(Dir[File.join(root, 'db', 'migrate', '*.rb')]).to be_empty
  end

  it 'prints upcoming cron times' do
    output = StringIO.new
    shell = Thor::Shell::Basic.new
    allow(shell).to receive(:stdout).and_return(output)

    cli = described_class.new([], {}, shell: shell)
    cli.invoke(:next, ['0 * * * *'], count: 2)

    lines = output.string.lines.map(&:strip).reject(&:empty?)
    expect(lines.length).to eq(2)
    expect(lines.first).to match(/T\d{2}:00:00Z/)
  end
end
