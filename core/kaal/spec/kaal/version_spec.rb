# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Kaal::VERSION' do
  it 'matches the gem version string' do
    expect(Kaal::VERSION).to eq('0.2.1')
  end
end
