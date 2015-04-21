require 'rspec'
require 'rspec/mocks'
require 'fakefs/spec_helpers'
require 'yaml'
require 'hussh'

RSpec.describe Hussh do
  include FakeFS::SpecHelpers

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

      describe 'before block' do
        let(:recorded_responses) do
          { 'host' => { 'user' => { 'cmd' => 'output' } } }
        end

        context 'with no params' do
          before do
            allow(@example).to receive(:metadata).and_return(
                                 {
                                   hussh: true,
                                   description: 'some spec',
                                   example_group: {
                                     description: 'example group',
                                     parent_example_group: {
                                       description: 'parent group'
                                     }
                                   }
                                 }
                               )
            FileUtils.mkdir_p('fixtures/hussh/parent group/example group')
            File.write(
              'fixtures/hussh/parent group/example group/some spec.yaml',
              recorded_responses.to_yaml
            )
            @before.call(@example)
          end

          it 'loads a recording with a generated name' do
            expect(Hussh.recorded_responses).to eq(recorded_responses)
          end
        end

        context 'with a string param' do
          before do
            allow(@example).to receive(:metadata).and_return(
                                 { hussh: 'group/spec' }
                               )
            FileUtils.mkdir_p('fixtures/hussh/group')
            File.write(
              'fixtures/hussh/group/spec.yaml',
              recorded_responses.to_yaml
            )
            @before.call(@example)
          end

          it 'uses the string as the recording name' do
            expect(Hussh.recorded_responses).to eq(recorded_responses)
          end
        end

        context 'with a hash param' do
          before do
            allow(@example).to receive(:metadata).and_return(
                                 {
                                   hussh: {
                                     recording_name: 'parent/spec'
                                   }
                                 }
                               )
            FileUtils.mkdir_p('fixtures/hussh/parent')
            File.write(
              'fixtures/hussh/parent/spec.yaml',
              recorded_responses.to_yaml
            )
            @before.call(@example)
          end

          it 'gets the recording_name from the hash' do
            expect(Hussh.recorded_responses).to eq(recorded_responses)
          end
        end
      end

      describe 'after block' do
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

