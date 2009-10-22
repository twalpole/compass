module Compass::CommandLineHelper
  def compass(*arguments)
    options = arguments.last.is_a?(Hash) ? arguments.pop : {}
    options[:wait] = 0.25
    if block_given?
      responder = Responder.new
      yield responder
      IO.popen("-", "w+") do |io|
        if io
          #parent process
          output = ""
          eof_at = nil
          while !eof_at || (Time.now - eof_at < options[:wait])
            if io.eof?
              eof_at ||= Time.now
              sleep 0.1
            else
              eof_at = nil
              timeout(1) do
                partial_output = io.readpartial(1024)
                # puts "))))#{partial_output}((((("
                output << partial_output
              end
              prompt = output.split("\n").last.strip
              if response = responder.response_for(prompt)
                io.puts response
              end
            end
          end
          responder.assert_required_responses!
          @last_result = output
        else
          #child process
          execute *arguments
        end
      end
    else
      @last_error = capture_warning do
        @last_result = capture_output do
          @last_exit_code = execute *arguments
        end
      end
    end
  rescue Timeout::Error
    fail "Read from child process timed out"
  end

  class Responder
    Response = Struct.new(:prompt, :text, :required, :responded)
    def initialize
      @responses = []
    end
    def respond_to(prompt, options = {})
      @responses << Response.new(prompt, options[:with], options[:required])
    end
    def response_for(prompt)
      response = @responses.detect{|r| r.prompt == prompt}
      if response
        response.responded = true
        response.text
      end
    end
    def assert_required_responses!
      @responses.each do |response|
        if response.required && !response.responded
          raise "Prompt not encountered: \"#{response.prompt}\""
        end
      end
    end
  end

  def assert_action_performed(action, path)
    actions_found = []
    @last_result.split("\n").each do |line|
      line = line.split
      return if line.first == action.to_s && line.last == path
      actions_found << line.first if line.last == path
    end
    message = "Action #{action.inspect} was not performed on: #{path}."
    message += "The following actions were performed: #{actions_found.join(", ")}" if actions_found.any?
    puts @last_result
    fail message
  end

  def within_tmp_directory(dir = "tmp")
    d = absolutize(dir)
    FileUtils.mkdir_p(d)
    Dir.chdir(d) do
      yield
    end
  ensure
    FileUtils.rm_rf(d)
  end

  def execute(*arguments)
    command_line_class = Compass::Exec::Helpers.select_appropriate_command_line_ui(arguments)
    command_line_class.new(arguments).run!
  end
end
