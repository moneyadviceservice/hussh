require 'rspec'
require 'rspec/mocks'
require 'fakefs/spec_helpers'
require 'yaml'

$: << '.'
require 'mallory'

RSpec.describe Mallory do
  include FakeFS::SpecHelpers

  describe Mallory::Session do
    describe :exec! do
      let(:real_session) do
        spy = instance_spy('Net::SSH::Connection::Session')
        allow(spy).to receive(:exec!) { |c| "#{c} output" }
        spy
      end
      before do
        Mallory.instance_eval { @commands_run = [] }
        allow(Net::SSH).to receive(:start_without_mallory)
                            .and_return(real_session)
      end

      context 'with a command that has not been run before' do
        before do
          Net::SSH.start('host', 'user') { |s| s.exec!('hostname') }
        end

        it 'runs the command via ssh' do
          expect(real_session).to have_received(:exec!).with('hostname')
        end

        it 'records that the command was run' do
          expect(Mallory.commands_run).to include('hostname')
        end

        it 'saves the result of the command' do
          expect(Mallory::Responses.recording['host']['user']['hostname'])
            .to eql('hostname output')
        end

        it 'flags the recording as changed' do
          expect(Mallory::Responses.recording_changed?).to eql(true)
        end
      end

      context 'with a command that has been run before' do
        before do
          FileUtils.mkdir_p 'fixtures/mallory'
          File.write(
            'fixtures/mallory/saved_responses.yaml',
            {
              'host' => { 'user' => { 'hostname' => "subsix\n" } }
            }.to_yaml
          )
          Mallory::Responses.load_recording('saved_responses')
          Net::SSH.start('host', 'user') { |s| s.exec!('hostname') }
        end

        it "doesn't run the command via ssh" do
          expect(Net::SSH).to_not have_received(:start_without_mallory)
        end

        it 'records that the command was run' do
          expect(Mallory.commands_run).to include('hostname')
        end

        it "doesn't flags the recording as changed" do
          expect(Mallory::Responses.recording_changed?).to eql(false)
        end
      end
    end
  end

  describe Mallory::Channel do
    before do
      Mallory.instance_eval { @commands_run = [] }
    end

    let!(:channel) do
      channel = instance_spy('Net::SSH::Connection::Channel')
      # Setup a fake Channel object which will hopefully behave like a
      # Net::SSH channel, i.e. register the command and callbacks, and then
      # call them all with the appropriate data and values.
      allow(channel).to receive(:exec) do |cmd, &block|
        @command = cmd
        @exec = block
      end
      allow(channel).to receive(:request_pty) { |&block| @request_pty = block }
      allow(channel).to receive(:on_data) { |&block| @on_data = block }
      allow(channel).to receive(:on_extended_data) do |&block|
        @on_extended_data = block
      end
      # TODO: loop and wait should also end up calling the callbacks
      allow(channel).to receive(:close) do
        # Allow the test to specify a command that fails.
        @exec.call(channel, !@command.match(/fail/)) if @exec
        # Allow the test to specify a failed pty request.
        @request_pty.call(channel, !@command.match(/nopty/)) if @request_pty
        @on_data.call(channel, "#{@command} output") if @on_data
        if @on_extended_data
          @on_extended_data.call(channel, "#{@command} stderr output")
        end
      end
      channel
    end

    let!(:session) do
      session = instance_spy('Net::SSH::Connection::Session')
      # The session here is just used to stub our channel in for the real one.
      allow(session).to receive(:open_channel).and_return(channel)
      allow(Net::SSH).to receive(:start_without_mallory).and_return(session)
      session
    end

    context 'when using exec with a block' do
      context 'the exec succeeded' do
        before do
          # Simulate how we would use Mallory, which sits between the
          # application code (the code below) and the mocked-out Net::SSH
          # code.
          Net::SSH.start('host', 'user') do |ssh|
            ssh.open_channel do |ch|
              ch.exec 'test' do |ch, success|
                @exec_success = success
                ch.request_pty
                ch.on_data          { |c, data| @data = data }
                ch.on_extended_data { |c, data| @extended_data = data }
              end
            end
          end
        end

        it 'gives us the stdout' do
          expect(@data).to eq 'test output'
        end

        it 'gives us the stderr' do
          expect(@extended_data).to eq 'test stderr output'
        end

        it 'allows us to request a pty' do
          expect(channel).to have_received(:request_pty)
        end

        it 'gives us the status of the exec' do
          expect(@exec_success).to eq true
        end

        it 'records that the command was run' do
          expect(Mallory.commands_run).to include('test')
        end

        it 'saves the result of the command' do
          expect(Mallory::Responses.recording['host']['user']['test'])
            .to eq 'test output'
        end

        it 'flags the recording as changed' do
          expect(Mallory::Responses.recording_changed?).to eql(true)
        end
      end

      context 'the exec has failed' do
        before do
          Net::SSH.start('host', 'user') do |ssh|
            ssh.open_channel do |ch|
              ch.exec('test-fail') { |ch, success| @exec_success = success }
            end
          end
        end
        subject { @exec_success }
        it { is_expected.to eq false }
      end


    end
    context 'when using exec without a block'
  end
end

