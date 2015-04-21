require 'rspec'
require 'rspec/mocks'
require 'fakefs/spec_helpers'
require 'yaml'
require 'hussh'

RSpec.describe Hussh do
  include FakeFS::SpecHelpers

  let(:session) { spy(Hussh::Session) }
  let(:channel) { Hussh::Channel.new(session) }
  let(:real_channel) do
    channel.instance_eval { @real_channel }
  end

  let(:mock_block) do
    block = Proc.new {}
    allow(block).to receive(:call)
    block
  end

  context 'real channel opened' do
    before do
      spy = instance_spy('Net::SSH::Connection::Channel')
      channel.instance_eval { @real_channel = spy }
    end

    describe :exec do
      context 'where there is no saved response' do
        before do
          allow(real_channel).to receive(:exec) do |command, &block|
            @command = command
            @hussh_block = block
          end
        end

        before do
          allow(session).to receive(:has_response?).and_return(false)
        end

        it 'records that the command was run' do
          channel.exec('record-command')
          expect(Hussh.commands_run.last).to eql('record-command')
        end

        context 'when a pty has been requested' do
          before { channel.instance_eval { @request_pty = true } }

          it 'requests a pty' do
            channel.exec('request-pty')
            expect(real_channel).to have_received(:request_pty)
          end
        end

        context 'when a pty has not been requested' do
          before { channel.instance_eval { @request_pty = false } }

          it 'does not request a pty' do
            channel.exec('no-request-pty')
            expect(real_channel).to_not have_received(:request_pty)
          end
        end

        context 'when an on_data block has been previously defined' do
          before { channel.instance_eval { @on_data_callback = Proc.new {} } }

          it 'sets up an on_data callback' do
            channel.exec('on-data')
            expect(real_channel).to have_received(:on_data)
          end
        end

        context 'when an on_data block has not been previously defined' do
          before { channel.instance_eval { @on_data_callback = nil } }

          it 'does not setup an on_data callback' do
            channel.exec('no-on-data')
            expect(real_channel).to_not have_received(:on_data)
          end
        end

        it 'calls our block' do
          channel.exec('block-command', &mock_block)
          @hussh_block.call(channel, 'test-for-success')
          expect(mock_block).to have_received(:call)
                                 .with(channel, 'test-for-success')
        end
      end

      context 'where there is a saved response' do
        before do
          allow(session).to receive(:has_response?).and_return(true)
        end

        it 'calls our block' do
          channel.exec('block-command') { @block_called = true }
          expect(@block_called).to eql(true)
        end
      end
    end

    describe :request_pty do
      before do
        allow(real_channel).to receive(:request_pty) { |&b| @hussh_block = b }
      end

      it 'calls request_pty on the real channel' do
        channel.request_pty
        expect(real_channel).to have_received(:request_pty)
      end

      it 'calls our block' do
        channel.request_pty(&mock_block)
        @hussh_block.call(channel, :status)
        expect(mock_block).to have_received(:call).with(channel, :status)
      end
    end

    describe :on_data do
      before do
        allow(real_channel).to receive(:on_data) { |&blk| @hussh_block = blk }
      end

      it 'calls on_data on the real channel' do
        channel.on_data {}
        expect(real_channel).to have_received(:on_data)
      end

      it 'calls our block' do
        channel.on_data(&mock_block)
        @hussh_block.call(channel, 'stdout')
        expect(mock_block).to have_received(:call).with(channel, 'stdout')
      end
    end

    describe :on_extended_data do
      before do
        allow(real_channel).to receive(:on_extended_data) do |&block|
          @hussh_block = block
        end
      end

      it 'calls on_extended_data on the real channel' do
        channel.on_extended_data {}
        expect(real_channel).to have_received(:on_extended_data)
      end

      it 'calls our block' do
        channel.on_extended_data(&mock_block)
        @hussh_block.call(channel, 'stderr')
        expect(mock_block).to have_received(:call).with(channel, 'stderr')
      end
    end

    describe :wait do
      it 'calls wait on the real channel' do
        channel.wait
        expect(real_channel).to have_received(:wait)
      end
    end
  end
end

