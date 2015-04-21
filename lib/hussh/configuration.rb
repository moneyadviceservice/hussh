module Hussh
  class Configuration
    def recordings_directory(directory)
      Hussh.recordings_directory = directory
    end

    def configure_rspec
      ::RSpec.configure do |config|
        recording_name_for = lambda do |metadata|
          if metadata.has_key?(:parent_example_group)
            recording_name_for[metadata[:parent_example_group]] +
              metadata[:description]
          elsif metadata.has_key?(:example_group)
            recording_name_for[metadata[:example_group]] +
              metadata[:description]
          else
            Pathname.new(metadata[:description])
          end
        end

        config.before(:each, hussh: lambda { |v| !!v }) do |example|
          options = example.metadata[:hussh]
          if options.is_a?(Hash)
            options = options.dup
            recording_name = options.delete(:recording_name) ||
                             recording_name_for[example.metadata]
          elsif options.is_a?(String)
            recording_name = options
            options = {}
          else
            recording_name = recording_name_for[example.metadata]
            options = {}
          end

          Hussh.load_recording(recording_name)
          Hussh.clear_stubbed_responses
        end

        config.after(:each, hussh: lambda { |v| !!v }) do |example|
          options = example.metadata[:hussh]
          options = options.is_a?(Hash) ? options.dup : {}
          Hussh.save_recording_if_changed
          Hussh.clear_recorded_responses
          Hussh.clear_stubbed_responses
          Hussh.commands_run.clear
        end
      end
    end
  end
end
