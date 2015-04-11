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

  describe Hussh::Channel do
    before do
      Hussh.commands_run.clear
      Hussh.clear_recorded_responses
      Hussh.clear_stubbed_responses
    end

    let!(:channel) do
      channel = instance_spy('Net::SSH::Connection::Channel')
      # Setup a fake Channel object which will hopefully behave like a
      # Net::SSH channel, i.e. register the command and callbacks, and then
      # call them all with the appropriate data and values.
      allow(channel).to receive(:exec) do |cmd, &blk|
        @command = cmd
        blk.call(channel, !@command.match(/-fail$/))
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
      allow(channel).to receive(:wait) do
        channel.close
      end
      channel
    end

    let!(:session) do
      session = instance_spy('Net::SSH::Connection::Session')
      # The session here is just used to stub our channel in for the real one.
      allow(session).to receive(:open_channel).and_yield(channel)
      allow(Net::SSH).to receive(:start_without_hussh).and_return(session)
      session
    end

    context 'when using an exec block' do
      before do
        FileUtils.mkdir_p 'fixtures/hussh'
        File.write('fixtures/hussh/saved_responses.yaml', saved_responses)
        Hussh.load_recording('saved_responses')

        # Simulate how we would use Hussh, which sits between the
        # application code (the code below) and the mocked-out Net::SSH
        # code.
        Net::SSH.start('host', 'user') do |session|
          session.open_channel do |ch|
            ch.request_pty
            ch.exec command do |ch, success|
              @exec_success = success
              ch.on_data          { |c, data| @data = data }
              ch.on_extended_data { |c, data| @extended_data = data }
            end
          end
        end
      end

      context 'with a command that has not been run before' do
        let(:saved_responses) { {}.to_yaml }

        context 'and execution is succesful' do
          let(:command) { 'test' }

          it 'runs the command via ssh' do
            expect(channel).to have_received(:exec).with('test')
          end

          it 'records that the command was run' do
            expect(Hussh.commands_run).to include('test')
          end

          it 'passes command status to exec' do
            expect(@exec_success).to eql(true)
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

          it 'saves the result of the command' do
            expect(Hussh.recorded_responses['host']['user']['test'])
              .to eq 'test output'
          end

          it 'flags the recording as changed' do
            expect(Hussh.recording_changed?).to eql(true)
          end
        end

        context 'and has failed to execute' do
          let(:command) { 'test-fail' }
          subject { @exec_success }
          it { is_expected.to eq false }
        end
      end

      context 'with a command that has recorded results' do
        let(:saved_responses) do
          {
            'host' => { 'user' => { 'test' => 'recorded test output' } }
          }.to_yaml
        end

        context 'and execution is succesful' do
          let(:command) { 'test' }

          it 'gives us the stdout' do
            expect(@data).to eq 'recorded test output'
          end

          it 'gives us the success status' do
            expect(@exec_success).to eql(true)
          end
        end
      end
    end
  end

  describe Hussh::Configuration do
    describe :configure_rspec do
      before do
        allow(Hussh).to receive(:save_recording_if_changed) do
          @saved_responses = Hussh.recorded_responses
        end
        allow(Hussh).to receive(:clear_recorded_responses)
        allow(Hussh).to receive(:clear_stubbed_responses)
        allow(Hussh.commands_run).to receive(:clear)
        rspec_spy = instance_spy(RSpec::Core::Configuration)
        allow(rspec_spy).to receive(:before) { |*args, &blk| @before = blk }
        allow(rspec_spy).to receive(:after) { |*args, &blk| @after = blk }
        allow(RSpec).to receive(:configure).and_yield(rspec_spy)
        Hussh.configure { |c| c.configure_rspec }
        @example = spy(RSpec::Core::Example)
        allow(@example).to receive(:metadata).and_return(
                             {
                               hussh: true,
                               description: 'Dis Iz A Mock'
                             })
      end

      context 'after block' do
        before do
          Hussh.recorded_responses = {
            'host' => { 'user' => { 'cmd' => 'output' } }
          }
          @after.call(@example)
        end

        it 'saves the recorded responses' do
          expect(Hussh).to have_received(:save_recording_if_changed)
          expect(@saved_responses).to(
            eq({'host' => {'user' => {'cmd' => 'output'}}})
          )
        end

        it 'clears the recorded responses' do
          expect(Hussh).to have_received(:clear_recorded_responses)
        end

        it 'clears stubbed responses' do
          expect(Hussh).to have_received(:clear_stubbed_responses)
        end

        it 'clears commands run' do
          expect(Hussh.commands_run).to have_received(:clear)
        end
      end
    end
  end
end

