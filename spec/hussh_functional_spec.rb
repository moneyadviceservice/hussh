require 'hussh'
require 'fakefs/spec_helpers'
require 'yaml'

RSpec.describe Hussh do
  include FakeFS::SpecHelpers

  # Setup a fake Channel object which will hopefully behave like a Net::SSH
  # channel, i.e. register the command and callbacks, and then call them all
  # with the appropriate data and in the right order.
  let!(:real_channel) do
    channel = instance_spy('Net::SSH::Connection::Channel')

    allow(channel).to receive(:exec) do |cmd, &block|
      @command = cmd
      # Allow the test to specify a command that fails.
      @success = !cmd.match(/fail/)
      block.call(channel, @success) if block
      output = "#{cmd} output"
      error_output = "#{cmd} error output"
      if cmd.match(/pty/) && !@request_pty
        output = nil
        error_output = 'no pty'
      end

      if output
        if @on_data
          @on_data.call(channel, output)
        else
          @on_data_pending = output
        end
      end

      if error_output
        if @on_extended_data
          @on_extended_data.call(channel, error_output)
        else
          @on_extended_data_pending = error_output
        end
      end
    end

    allow(channel).to receive(:request_pty) do |&block|
      block.call(channel, true) if block
      @request_pty = true
    end

    allow(channel).to receive(:on_data) do |&block|
      @on_data = block
      if @on_data_pending
        block.call(channel, @on_data_pending)
        @on_data_pending = nil
      end
    end

    allow(channel).to receive(:on_extended_data) do |&block|
      @on_extended_data = block
      if @on_extended_data_pending
        block.call(channel, @on_extended_data_pending)
        @on_extended_data_pending = nil
      end
    end

    channel
  end

  # Inject our "real_channel" above into code that uses Net::SSH
  let!(:real_session) do
    session = instance_spy('Net::SSH::Connection::Session')
    allow(session).to receive(:exec!) { |c| "#{c} output" }
    allow(session).to receive(:open_channel) do |&blk|

      blk.call(real_channel) if blk
      real_channel
    end
    allow(Net::SSH).to receive(:start_without_hussh).and_return(session)
    session
  end

  let(:saved_responses) { {}.to_yaml }


  before do
    Hussh.commands_run.clear
    Hussh.clear_stubbed_responses

    FileUtils.mkdir_p 'fixtures/hussh'
    File.write('fixtures/hussh/saved_responses.yaml', saved_responses)
    Hussh.load_recording('saved_responses')
  end

  describe :exec! do
    context 'with a command that has not been run before' do
      before do
        Net::SSH.start('host', 'user') do |s|
          @output = s.exec!('id')
        end
      end

      it 'runs the command via ssh' do
        expect(real_session).to have_received(:exec!).with('id')
      end

      it 'records that the command was run' do
        expect(Hussh.commands_run).to include('id')
      end

      it 'returns the result of the command' do
        expect(@output).to eql("id output")
      end

      it 'saves the result of the command' do
        expect(Hussh.recorded_responses['host']['user']['id'])
          .to eql("id output")
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

  describe 'using callbacks defined after exec and no pty' do
    before do
      # Simulate how we would use Hussh, which sits between the
      # application code (the code below) and the mocked-out Net::SSH
      # code.
      Net::SSH.start('host', 'user') do |session|
        session.open_channel do |ch|
          ch.exec command
          ch.on_data          { |c, data| @data = data }
          ch.on_extended_data { |c, data| @extended_data = data }
        end
      end
    end

    let(:command) { 'callbacks-after' }

    it 'runs the command via ssh' do
      expect(real_channel).to have_received(:exec).with(command)
    end

    it 'records the command was run' do
      expect(Hussh.commands_run).to include(command)
    end

    it 'gives us the stdout' do
      expect(@data).to eq "#{command} output"
    end

    it 'gives us the stderr' do
      expect(@extended_data).to eq "#{command} error output"
    end

    context 'with a command that requires a pty' do
      let(:command) { 'test-pty-fail' }

      it 'has no stdout' do
        expect(@data).to eq nil
      end

      it 'signals error on stderr' do
        expect(@extended_data).to eq 'no pty'
      end
    end

    context 'with saved responses' do
      let(:saved_responses) do
        {
          'host' => { 'user' => { command => "recorded #{command} output" } }
        }.to_yaml
      end

      it 'gives us the recorded stdout' do
        expect(@data).to eq "recorded #{command} output"
      end
    end
  end

  describe 'callbacks defined before exec and no pty' do
    before do
      # Callbacks defined before the exec should still be called.
      Net::SSH.start('host', 'user') do |session|
        session.open_channel do |ch|
          ch.on_data          { |c, data| @data = data }
          ch.on_extended_data { |c, data| @extended_data = data }
          ch.exec 'callbacks-before'
        end
      end
    end

    it 'runs the command via ssh' do
      expect(real_channel).to have_received(:exec).with('callbacks-before')
    end

    it 'records the command was run' do
      expect(Hussh.commands_run).to include('callbacks-before')
    end

    it 'gives us the stdout' do
      expect(@data).to eq 'callbacks-before output'
    end

    it 'gives us the stderr' do
      expect(@extended_data).to eq 'callbacks-before error output'
    end
  end

  describe 'requesting a pty' do
    before do
      # Request a pty before we run exec.
      Net::SSH.start('host', 'user') do |session|
        session.open_channel do |ch|
          ch.request_pty
          ch.exec 'test-pty'
        end
      end
    end

    it 'requests a pty' do
      expect(real_channel).to have_received(:request_pty)
    end
  end

  describe 'using an exec block' do
    before do
      # Use Net::SSH and our callbacks defined in the exec block.
      Net::SSH.start('host', 'user') do |session|
        session.open_channel do |ch|
          ch.exec command do |ch, success|
            @exec_success = success
            ch.on_data          { |c, data| @data = data }
            ch.on_extended_data { |c, data| @extended_data = data }
          end
        end
      end
    end

    let(:command) { 'block-test' }

    it 'runs the command via ssh' do
      expect(real_channel).to have_received(:exec).with(command)
    end

    it 'records that the command was run' do
      expect(Hussh.commands_run).to include(command)
    end

    it 'passes command status to exec' do
      expect(@exec_success).to eql(true)
    end

    it 'gives us the stdout' do
      expect(@data).to eq "#{command} output"
    end

    it 'gives us the stderr' do
      expect(@extended_data).to eq "#{command} error output"
    end

    it 'saves the result of the command' do
      expect(Hussh.recorded_responses['host']['user'][command])
        .to eq "#{command} output"
    end

    it 'flags the recording as changed' do
      expect(Hussh.recording_changed?).to eql(true)
    end

    context 'with a failed connection' do
      let(:command) { 'test-fail' }
      subject { @exec_success }
      it { is_expected.to eq false }
    end

    context 'with a command that has recorded results' do
      let(:command) { 'recorded-test' }
      let(:saved_responses) do
        {
          'host' => { 'user' => { 'test-recorded' => "#{command} output" } }
        }.to_yaml
      end

      it 'gives us the stdout' do
        expect(@data).to eq "#{command} output"
      end

      it 'gives us the success status' do
        expect(@exec_success).to eql(true)
      end
    end
  end
end
