require 'net/ssh'
require 'pry'
require 'logger'

module Net
  module SSH
    class << self
      def start_with_mallory(host, user, options = {}, &block)
        if Mallory::Responses.has_recording? || Mallory.allow_connections?
          session = Mallory::Session.new(host, user)
          if block_given?
            yield session
            session.close
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

  def self.commands_run
    @@commands_run ||= []
  end

  class Configuration
    def recordings_directory(directory)
      Mallory::Responses.recordings_directory = directory
    end

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
          Mallory.commands_run.clear
        end
      end
    end
  end

  class Session
    def initialize(host, user)
      @host = host
      @user = user
      @responses = Responses.responses_for_host_and_user(host, user)
      @recording = Responses.recording[host][user]
    end

    def real_session
      @real_session ||= Net::SSH.start_without_mallory(@host, @user)
    end

    def responses
      @responses
    end

    def exec!(command)
      Mallory.commands_run << command
      if @responses.has_response? command
        @responses[command]
      else
        response = real_session.exec! command
        Responses.recording_changed = true
        @recording[command] = response
      end
    end

    def open_channel(&block)
      @channel = Channel.new(self)
      block.call(@channel)
      @channel.close
      @recording[@channel.command_executed] = @channel.response_data
      Responses.recording_changed = true
    end

    def close
      @real_session.close if @real_session
      @real_session = nil
    end
  end

  class Channel
    def initialize(session)
      @session = session
      @request_pty = false
    end

    def real_channel
      @real_channel ||= @session.real_session.open_channel
    end

    def response_data
      @data
    end

    def command_executed
      @command
    end

    def request_pty(&block)
      @request_pty = true
      @request_pty_block = block
    end

    def exec(command, &block)
      Mallory.commands_run << @command = command
      if block_given?
        real_channel.exec(command) do |ch, success|
          block.call(self, success)
        end
      end
    end

    def close
      @real_channel.close if @real_channel
    end

    def on_data(&block)
      real_channel.on_data do |ch, data|
        @data ||= ''
        @data += data
        block.call(ch, data)
      end
    end

    def on_extended_data(&block)
      real_channel.on_extended_data do |ch, data|
        @extended_data ||= []
        @extended_data << data
        block.call(ch, data)
      end
    end

    def request_pty(&block)
      if block_given?
        real_channel.request_pty do |ch, success|
          @request_pty_success = success
          block.call(ch, success)
        end
      else
        real_channel.request_pty
      end
    end

    def on_close(&block)
      @on_close = block
    end
  end

  class Responses
    @@recording = {}
    @@recording_changed = false
    @@recordings_directory = 'fixtures/mallory'

    def self.recordings_directory=(directory)
      @@recordings_directory = directory
    end

    def self.recording_path(name)
      "#{@@recordings_directory}/#{name}.yaml"
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
      Responses.new(host, user)
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

