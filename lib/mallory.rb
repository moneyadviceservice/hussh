require 'net/ssh'
require 'pry'

module Net
  module SSH
    class << self
      def start_with_mallory(host, user, options = {}, &block)
        session = Mallory::Session.new(host, user)
        if block_given?
          yield session
        else
          session
        end
      end
      alias_method :start_without_mallory, :start
      alias_method :start, :start_with_mallory
    end
  end
end


module Mallory
  def self.use_recording name
    filename = "fixtures/mallory_recordings/#{name}.yaml"
    if File.exist? filename
      Responses.saved_responses = YAML.load_file filename
    else
      Responses.saved_responses = {}
    end
    Responses.saved_responses_changed = false
  end

  def self.save_recording name
    filename = "fixtures/mallory_recordings/#{name}.yaml"
    if Responses.saved_responses_changed
      File.write(filename, Responses.saved_responses.to_yaml)
      Responses.saved_responses_changed = false
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

    def exec!(command)
      if @responses.has_response? command
        @responses[command]
      else
        Responses.saved_responses_changed = true
        response = real_connection.exec! command
        Responses.saved_responses[@host][@user][command] = response
      end
    end
  end


  class Responses
    @@saved_responses = {}
    @@saved_responses_changed = false

    def self.saved_responses
      @@saved_responses
    end

    def self.saved_responses=(responses)
      @@saved_responses = responses
    end

    def self.saved_responses_changed
      @@saved_responses_changed
    end

    def self.saved_responses_changed=(changed)
      @@saved_responses_changed = changed
    end

    def self.responses_for_host_and_user(host, user)
      @@saved_responses[host] ||= {}
      @@saved_responses[host][user] ||= {}
      Responses.new(host, user)
    end

    def self.register_response(host, user, command, response = nil, &block)
      @@saved_responses[host] ||= {}
      @@saved_responses[host][user] ||= {}
      @@saved_responses[host][user][command] = block_given? ? block : response
    end

    def initialize(host, user)
      @host = host
      @user = user
      @test_responses = {}
    end

    def has_response?(command)
      @test_responses.has_key?(command) || \
        @@saved_responses[@host][@user].has_key?(command)
    end

    def [](command)
      @test_responses.fetch(command, @@saved_responses[@host][@user][command])
    end

    def []=(command, value)
      # if @responses.has_key?(command) && @responses[command].responds_to?(:call)
      #   raise "Could not overwrite callable response #{command} for #{@user}@#{@host}"
      # end
      @test_responses[command] = value
    end
  end
end

