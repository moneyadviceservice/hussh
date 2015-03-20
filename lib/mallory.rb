require 'net/ssh'
require 'pry'

module Net
  module SSH
    class << self
      def start_with_mallory(host, user, options = {}, &block)
        if Mallory::Responses.has_recording? || Mallory.allow_connections?
          session = Mallory::Session.new(host, user)
          if block_given?
            yield session
          else
            session
          end
        end
      end
      alias_method :start_without_mallory, :start
      alias_method :start, :start_with_mallory
    end
  end
end


module Mallory
  def self.allow_connections?
    @allow_connections ||= false
  end

  def self.allow_connections
    @allow_connections = true
  end

  def self.disallow_connections
    @allow_connections = false
  end

  def self.configure
    yield configuration
  end

  def self.configuration
    @configuration ||= Configuration.new
  end

  class Configuration
    def configure_rspec
      ::RSpec.configure do |config|
        recording_name_for = lambda do |metadata|
          if metadata.has_key? :parent_example_group
            recording_name_for[metadata[:parent_example_group]] +
              metadata[:description]
          elsif metadata.has_key? :example_group
            recording_name_for[metadata[:example_group]] +
              metadata[:description]
          else
            Pathname.new(metadata[:description])
          end
        end

        config.before(:each, mallory: lambda { |v| !!v }) do |example|
          options = example.metadata[:mallory]
          options = options.is_a?(Hash) ? options.dup : {}
          recording_name = options.delete(:recording_name) ||
                           recording_name_for[example.metadata]
          Responses.load_recording(recording_name)
        end

        config.after(:each, mallory: lambda { |v| !!v }) do |example|
          options = example.metadata[:mallory]
          options = options.is_a?(Hash) ? options.dup : {}
          recording_name = options.delete(:recording_name) ||
                           recording_name_for[example.metadata]
          Responses.save_recording recording_name
          Responses.recording.clear
        end
      end
    end
  end

  class Session
    def initialize(host, user)
      @host = host
      @user = user
      @responses = Responses.responses_for_host_and_user(host, user)
    end

    def real_connection
      @real_connection ||= Net::SSH.start_without_mallory(@host, @user)
    end

    def session_commands
      @session_commands ||= []
    end

    def exec!(command)
      session_commands << command
      if @responses.has_response? command
        @responses[command]
      else
        Responses.recording_changed = true
        response = real_connection.exec! command
        Responses.recording[@host][@user][command] = response
      end
    end
  end


  class Responses
    @@recording = {}
    @@recording_changed = false

    def self.recording_path(name)
      "fixtures/#{name}.yaml"
    end

    def self.recording
      @@recording
    end

    def self.recording=(responses)
      @@recording = responses
    end

    def self.has_recording?
      !!@@recording
    end

    def self.recording_changed?
      @@recording_changed
    end

    def self.recording_changed=(new_value)
      @@recording_changed = new_value
    end

    def self.responses_for_host_and_user(host, user)
      @@recording[host] ||= {}
      @@recording[host][user] ||= {}
      Recording.new(host, user)
    end

    def self.register_response(host, user, command, response = nil, &block)
      @@recording[host] ||= {}
      @@recording[host][user] ||= {}
      @@recording[host][user][command] = block_given? ? block : response
    end

    def self.load_recording(name)
      path = recording_path(name)
      if File.exist? path
        self.recording = YAML.load_file path
      else
        self.recording = {}
      end
      self.recording_changed = false
    end

    def self.save_recording name
      path = recording_path(name)
      if self.recording_changed?
        if !File.exist? path
          FileUtils.mkdir_p(File.dirname(path))
        end
        File.write(path, recording.to_yaml)
        self.recording_changed = false
      end
    end

    def initialize(host, user)
      @host = host
      @user = user
      @responses = {}
    end

    def has_response?(command)
      @responses.has_key?(command) || \
        @@recording[@host][@user].has_key?(command)
    end

    def [](command)
      @responses.fetch(command, @@recording[@host][@user][command])
    end

    def []=(command, value)
      @responses[command] = value
    end
  end
end

