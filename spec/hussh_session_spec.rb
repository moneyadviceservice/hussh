require 'rspec'
require 'rspec/mocks'
require 'fakefs/spec_helpers'
require 'yaml'
require 'hussh'

RSpec.describe Hussh do
  include FakeFS::SpecHelpers
  describe Hussh::Session do
    describe :exec! do
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

      context 'with a command that has not been run before' do
        before do
          Net::SSH.start('host', 'user') { |s| @output = s.exec!('hostname') }
        end

        it 'runs the command via ssh' do
          expect(real_session).to have_received(:exec!).with('hostname')
        end

        it 'records that the command was run' do
          expect(Hussh.commands_run).to include('hostname')
        end

        it 'returns the result of the command' do
          expect(@output).to eql('hostname output')
        end

        it 'saves the result of the command' do
          expect(Hussh.recorded_responses['host']['user']['hostname'])
            .to eql('hostname output')
        end

        it 'flags the recording as changed' do
          expect(Hussh.recording_changed?).to eql(true)
        end
      end

      context 'with a command that has been run before' do
        before do
          FileUtils.mkdir_p 'fixtures/hussh'
          File.write(
            'fixtures/hussh/saved_responses.yaml',
            {
              'host' => { 'user' => { 'hostname' => "subsix\n" } }
            }.to_yaml
          )
          Hussh.load_recording('saved_responses')
          Net::SSH.start('host', 'user') { |s| s.exec!('hostname') }
        end

        it "doesn't run the command via ssh" do
          expect(Net::SSH).to_not have_received(:start_without_hussh)
        end

        it 'records that the command was run' do
          expect(Hussh.commands_run).to include('hostname')
        end

        it "doesn't flags the recording as changed" do
          expect(Hussh.recording_changed?).to eql(false)
        end
      end
    end
  end
end
