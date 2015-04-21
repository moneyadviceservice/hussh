require 'rspec'
require 'rspec/mocks'
require 'fakefs/spec_helpers'
require 'yaml'
require 'hussh'

RSpec.describe Hussh do
  include FakeFS::SpecHelpers

  describe Hussh::Session do
    let(:real_session) do
      spy = instance_spy('Net::SSH::Connection::Session')
      allow(spy).to receive(:exec!) { |c| "#{c} output" }
      spy
    end

    before do
      Hussh.commands_run.clear
      Hussh.clear_recorded_responses
      Hussh.clear_stubbed_responses
      allow(Net::SSH).to receive(:start_without_hussh)
                          .and_return(real_session)
    end

    describe :open_channel do
      let(:session) { Hussh::Session.new('host', 'user') }

      it 'returns a new channel' do
        @channel = session.open_channel
        expect(@channel).to be_a(Hussh::Channel)
      end

      it 'runs the given block' do
        session.open_channel do |ch|
          @channel = ch
        end
        expect(@channel).to be_a(Hussh::Channel)
      end
    end
  end
end
