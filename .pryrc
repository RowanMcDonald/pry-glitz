ENV['HOME'] ||= ENV['USERPROFILE'] || File.dirname(__FILE__)

$pryrc_errors = []

class String
  def tilde; sub ENV['HOME'], '~'; end;
  def colour(name); "\001#{Pry::Helpers::Text.send name, '{self}'}\002".sub('{self}', "\002#{self}\001"); end
  # I feel like this could be an actual rainbow...
  def rainbow(i); colour %w(purple blue cyan green yellow red)[i % 6]; end
end

@settings = 0
def set(msg)
  yield
  puts " │ ".colour(:bright_black) + "#{msg.()}".rainbow(@settings)
  @settings += 1
rescue => e
  $pryrc_errors << e
  puts " │ ".colour(:bright_black) + "🚨 #{e.to_s.colour(:bright_red)} 🚨"
end

puts "\n"
puts (' ╭' + '─'*3 + ' Loading ~/.pryrc ' + '─' * 42).colour(:bright_black)
puts ' │'.colour(:bright_black)

set -> { 'Configuring a moody prompt' } do
  rspec_match = /#<RSpec::ExampleGroups::(.*)::(.*)>$/

  moods = [ '⁽(◍˃̵͈̑ᴗ˂̵͈̑)⁽', '(ﾉ^ヮ^)ﾉ*:・ﾟ✧', '༼ つ ͠° ͟ ͟ʖ ͡° ༽つ', 'ల(*´= ◡ =｀*)', '(⊙﹏⊙✿)', 'ʕ •́؈•̀ ₎', '✌.ʕʘ‿ʘʔ.✌', 'ʕ•̼͛͡•ʕ-̺͛͡•ʔ•̮͛͡•ʔ', '⊹⋛⋋( ՞ਊ ՞)⋌⋚⊹' ].shuffle
  decor = [' '] + ['・', 'ﾟ', '✧', '*', '✿', '⊹'].shuffle
  decorate = -> (context) { decor.take(4).inject(context) { |ctx, ✨| ✨ + ctx+ ✨ } }

  prompts = [
    proc { |target_self, nest_level, pry|
      context = Pry.view_clip(target_self)

      if m = context.match(rspec_match)
        context = defined?(Rails) ? m[2].underscore.humanize : m[2]
        "👾 " + decorate.(context).colour(:blue) + ' '.colour(:white)
      else
        "🎒 " + decorate.(context).colour(:blue) + ' '.colour(:white)
      end
    },
    proc { |target_self, nest_level, pry|
      moods[nest_level].colour(:bright_black) + ' '
    }
  ]

  if Pry::VERSION < '0.12.1'
    Pry.config.prompt = prompts
  else
    Pry.config.prompt = Pry::Prompt.new("pretty", "pretty", prompts)
  end
end

set -> { "Setting your editor to #{Pry.editor}" } do
  Pry.editor = ENV['VISUAL']
end


if Pry.config.history.respond_to? :file=
  set -> { "Writing history to #{Pry.config.history.file.tilde}" } do
    Pry.config.history.file = File.expand_path('~/.history.rb')
  end
else
  set -> { "Writing history to #{Pry.config.history_file.tilde}" } do

    Pry.config.history_file = File.expand_path('~/.history.rb')
  end
end


if defined?(Rails)
  levels = [:debug, :info, :warn, :error, :fatal, :unknown]
  org_logger_active_record = org_logger_rails = org_level = nil

  logger = Logger.new(STDOUT).tap do |logger|
    logger.formatter = proc { |sev, time, progname, msg| "[#{sev}] #{' ' * (5 - sev.length)}- #{msg} at #{time}\n" }
    logger.level = Logger::ERROR if Rails.const_defined?("Console")
  end

  set -> { "Overridding Rails.logger" } do
    Pry.hooks.add_hook :before_session, :rails do |output, target, pry|
      org_logger_rails = Rails.logger
      org_logger_active_record = ActiveRecord::Base.logger
      Rails.logger = ActiveRecord::Base.logger = logger
      if defined?(SemanticLogger) && app = SemanticLogger.appenders.find { |a| !a.instance_variable_get('@file_name') }
        org_level = app.level
        app.level = :error
      end
    end

    Pry.hooks.add_hook :after_session, :rails do |output, target, pry|
      ActiveRecord::Base.logger = org_logger_active_record if org_logger_active_record
      Rails.logger = org_logger_rails if org_logger_rails
      SemanticLogger.appenders.find { |a| !a.instance_variable_get('@file_name') }.level =  org_level if org_level
    end
  end
end

set -> { "Loading plugins: #{Pry.plugins.keys.map{|s| 'pry-' + s }.join(', ')}" } do
  begin
    Pry.load_plugins if Pry.config.should_load_plugins
  rescue => e
    puts "  !! could not load plugins"
  end
end


set -> { "Adding Array#first! #{"and ActiveRecord::Relation#first!" if defined?(ActiveRecord) }" } do
  class Array
    def first!
      raise 'more than one element' if (respond_to?(:count) && count > 1) || length > 1
      self[0]
    end
  end

  if defined?(ActiveRecord)
    class ActiveRecord::Relation
      def first!
        raise 'more than one element' if (respond_to?(:count) && count > 1) || length > 1
        self[0]
      end
    end
  end
end

if RUBY_PLATFORM =~ /darwin/i # OSX only.
  set -> { 'Warming up pbcopy and pbpaste 🔥' } do
    def pbcopy(data)
      IO.popen 'pbcopy', 'w' do |io|
        io << data
      end
      nil
    end

    def pbpaste
      `pbpaste`
    end
  end

  if (require 'awesome_print' rescue false)
    set -> { 'Copy last result with cp, -m for multiline' } do
      Pry.config.commands.command "cp", "Copy last result to clipboard, -m for multiline copy" do
        multiline = arg_string == '-m'
        pbcopy pry_instance.last_result.ai(plain: true, indent: 2, index: false, multiline: multiline)
        output.puts "    📄 copied#{multiline ? ' multiline!' : '!'}"
      end
    end
  end
end

# Pry defaults to including line numbers.  This changes that.
set -> { 'Adding his, history without line numbers' } do
  Pry.config.commands.alias_command "hi", "hist -n", desc: "hist without line numbers"
end

set -> { '`ims` gives you methods specific to that object' } do
  class Object
    def ims
      (self.methods - Object.instance_methods).sort
    end
  end
end

remove_instance_variable '@settings'
undef :set
class String
  undef :tilde
  undef :rainbow
end
# puts ' │'.colour(:bright_black)
puts (' ╰' + '─' * 63).colour(:bright_black)
if $pryrc_errors.any?
  puts "  Loading your ~/.pryrc file raised #{$pryrc_errors.size} error(s)."
  puts "  Inspect them by looking at $pryrc_errors."
end
puts
