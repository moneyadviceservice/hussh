require 'net/ssh'
require 'pry'
require 'logger'

module Net
  module SSH
    class << self
      def start_with_mallory(host, user, options = {}, &block)
        # TODO: Let's do this later once everything else is working.
        # if Mallory.has_recording? || Mallory.allow_connections?
        session = Mallory::Session.new(host, user)
        if block_given?
          yield session
          session.close
        else
          session
        end
        # end
      end
      alias_method :start_without_mallory, :start
      alias_method :start, :start_with_mallory
    end
  end
end


def mattr_accessor(*syms)
  syms.each do |sym|
    class_eval(<<EOD)
@@#{sym} = nil unless defined? @@#{sym}
def self.#{sym}
  @@#{sym}
end

def self.#{sym}=(obj)
  @@#{sym} = obj
end
EOD
  end
end

module Mallory
  def self.allow_connections?
    @@allow_connections ||= false
  end

  def self.allow_connections!
    @@allow_connections = true
  end

  def self.disallow_connections
    @@allow_connections = false
  end

  def self.configure
    yield configuration
  end

  def self.configuration
    @@configuration ||= Configuration.new
  end

  def self.commands_run
    @@commands_run ||= []
  end

  @@recordings_directory = 'fixtures/mallory'
  mattr_accessor :recordings_directory
  mattr_accessor :stubbed_responses, :recorded_responses

  def self.has_recording?
    !!@@recorded_responses
  end

  def self.load_recording(name)
    @@recording_path = self.path_for_recording(name)
    @@recording_changed = false
    if File.exist?(@@recording_path)
      @@recorded_responses = YAML.load_file(@@recording_path)
    else
      self.clear_recorded_responses
    end
  end

  def self.save_recording_if_changed
    return if !self.recording_changed?
    @@recording_path ||= self.path_for_recording(name)
    if !File.exist?(@@recording_path)
      FileUtils.mkdir_p(File.dirname(@@recording_path))
    end
    File.write(@@recording_path, @@recorded_responses.to_yaml)
    @@recording_changed = false
  end

  def self.clear_recorded_responses
    @@recorded_responses = {}
  end

  def self.recording_changed?
    @@recording_changed
  end

  def self.recording_changed!
    @@recording_changed = true
  end

  def self.clear_stubbed_responses
    @@stubbed_responses = {}
  end

  # private
  def self.path_for_recording(name)
    "#{@@recordings_directory}/#{name}.yaml"
  end

  class Configuration
    def recordings_directory(directory)
      Mallory.recordings_directory = directory
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

        config.before(:each, mallory: lambda { |v| !!v }) do |example|
          options = example.metadata[:mallory]
          options = options.is_a?(Hash) ? options.dup : {}
          recording_name = options.delete(:recording_name) ||
                           recording_name_for[example.metadata]
          Mallory.load_recording(recording_name)
          Mallory.clear_stubbed_responses
        end

        config.after(:each, mallory: lambda { |v| !!v }) do |example|
          options = example.metadata[:mallory]
          options = options.is_a?(Hash) ? options.dup : {}
          Mallory.clear_recorded_responses
          Mallory.clear_stubbed_responses
          Mallory.commands_run.clear
        end
      end
    end
  end

  class Session
    def initialize(host, user)
      @host = host
      @user = user
    end

    def real_session
      @real_session ||= Net::SSH.start_without_mallory(@host, @user)
    end

    def has_response?(command)
      Mallory.stubbed_responses.fetch(@host, {}).fetch(@user, {})
        .has_key?(command) ||
        Mallory.recorded_responses.fetch(@host, {}).fetch(@user, {})
        .has_key?(command)
    end

    def response_for(command)
      Mallory.stubbed_responses.fetch(@host, {}).fetch(@user, {}).fetch(
        command,
        Mallory.recorded_responses.fetch(@host, {}).fetch(@user, {})[command]
      )
    end

    def update_recording(command, response)
      Mallory.recorded_responses[@host] ||= {}
      Mallory.recorded_responses[@host][@user] ||= {}
      Mallory.recorded_responses[@host][@user][command] = response
      Mallory.recording_changed!
    end

    def exec!(command)
      Mallory.commands_run << command
      if self.has_response?(command)
        self.response_for(command)
      else
        response = real_session.exec!(command)
        self.update_recording(command, response)
      end
    end

    def open_channel(&block)
      @channel = Channel.new(self)
      block.call(@channel)
      Mallory.commands_run << @channel.command
      if self.has_response?(@channel.command)
        if @channel.exec_block.respond_to?(:call)
          @channel.exec_block.call(@channel, true)
        end

        if @channel.on_data_block.respond_to?(:call)
          @channel.on_data_block.call(@channel, self.response_for(@channel.command))
        end
      else
        self.real_session.open_channel do |ch|
          ch.exec(@channel.command) do |ch, success|
            if @channel.exec_block.respond_to?(:call)
              @channel.exec_block.call(@channel, success)
            end
          end

          if @channel.on_data_block.respond_to?(:call)
            ch.on_data do |ch, output|
              @channel.on_data_block.call(@channel, output)
              @on_data = output
              # TODO: Move below logic into update_recording?
              # if !@on_data
              #   @on_data = output
              # else
              #   @on_data = [@on_data] if !@on_data.is_a? Array
              #   @on_data << output
              # end
              self.update_recording(@channel.command, @on_data)
            end
          end

          ch.on_extended_data do |ch, output|
            if @channel.on_extended_data_block.respond_to?(:call)
              @channel.on_extended_data_block.call(@channel, output)
            end

            # TODO: We don't have a way to record this yet.
            # if !@on_extended_data
            #   @on_extended_data = output
            # else
            #   if !@on_extended_data.is_a? Array
            #     @on_extended_data = [@on_extended_data]
            #   end
            #   @on_extended_data << output
            # end
          end

          ch.request_pty do |ch, success|
            # TODO: We need a way to record this
            if @channel.request_pty_block.respond_to?(:call)
              @channel.request_pty_block.call(ch, success)
            end
          end

          # TODO: Should wait be here or should it be in the calling code?
          ch.wait
        end
      end
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

    attr :command
    attr :exec_block
    def exec(command, &block)
      @command = command
      @exec_block = block
    end

    attr :on_data_block
    def on_data(&block)
      @on_data_block = block
    end

    attr :on_extended_data_block
    def on_extended_data(&block)
      @on_extended_data_block = block
    end

    attr :request_pty_block
    def request_pty(&block)
      @request_pty = true
      @request_pty_block = block
    end

    def requested_pty?
      @request_pty
    end

    # def on_close(&block)
    #   @on_close = block
    # end

    # def close
    #   @real_channel.close if @real_channel
    # end
  end
end

