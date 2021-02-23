require 'multish/version'

require 'curses'
require 'open3'
require 'colorize'

BRIGHT_WHITE = 15

class MultishItem
  attr_reader :command

  def initialize(command, index, count)
    @command = command
    @index = index
    @count = count
    @output = ''
  end

  def width
    (Curses.cols / @count).floor
  end

  def height
    Curses.lines
  end

  def left
    width * @index
  end

  def top
    0
  end

  def create_window!
    @nav_window = Curses::Window.new(1, width - 1, top, left)
    @window = Curses::Window.new(height - 1, width - 1, top + 1, left)
    @window.scrollok(true)
    update_title!
  end

  def color_code
    if !@wait_thr
      4
    elsif finished?
      errored? ? 3 : 2
    else # rubocop:disable Lint/DuplicateBranch
      4
    end
  end

  def errored?
    @exit_code && @exit_code != 0
  end

  def update_title!
    @nav_window.setpos(0, 0)
    @nav_window.attron(Curses.color_pair(color_code) | Curses::A_REVERSE | Curses::A_BOLD)
    @nav_window.addstr(window_title.ljust(width - 1))
    @nav_window.refresh
  end

  def window_title
    finished? ? "[ #{command} ] -> #{@exit_code}" : "$ #{command}"
  end

  def open_process!
    @stdin, @stdout, @stderr, @wait_thr = Open3.popen3(@command)
    @stdin.close
  end

  def streams
    [@stdout, @stderr]
  end

  def try_update(fd) # rubocop:disable Naming/MethodParameterName
    return unless [@stdout, @stderr].include?(fd)

    line = fd.gets
    print(line) if line
  end

  def print(text)
    @output << text
    color_print(@window, text)
    @window.refresh
  end

  def color_print(window, input)
    parse_commands(input) do |op, arg|
      case op
      when :string
        window.addstr(arg)
      when :reset
        window.attroff(Curses.color_pair(10) | Curses::A_BOLD)
      when :bold
        window.attron(Curses::A_BOLD)
      when :color
        Curses.init_pair(10, arg, BRIGHT_WHITE)
        window.attron(Curses.color_pair(10))
      when :error
        raise "ERROR: #{arg}"
      end
    end
  end

  def parse_commands(string)
    parse_string(string) do |op, arg|
      case op
      when :string
        yield [:string, arg]
      when :escape
        if arg == '[m'
          yield [:reset]
        elsif arg[/^\[(\d+;)+(\d+)m$/]
          args = ($1 + $2).split(';')
          args.each do |subarg|
            subarg = subarg.to_i
            case subarg
            when 1
              yield [:bold]
            when 30..37
              color = Curses::COLOR_BLACK + subarg - 30
              yield [:color, color]
            end
          end
        end
      when :error
        yield [:error, arg]
      end
    end
  end

  def parse_string(string)
    len = string.length
    i = 0
    chars = ''
    while i < len
      char = string[i]
      if char == "\e"
        yield [:string, chars] if !chars.empty? && block_given?
        chars = ''
        escape = ''
        i += 1
        if string[i] == '['
          escape << string[i]
          i += 1
        else
          return yield [:error, string]
        end
        while string[i] =~ /[\x30-\x3f]/
          escape << string[i]
          i += 1
        end
        while string[i] =~ /[\x20–\x2f]/
          escape << string[i]
          i += 1
        end
        if string[i] =~ /[\x40-\x7e]/
          escape << string[i]
        else
          return yield [:error, string]
        end
        yield [:escape, escape] if block_given?
      else
        chars << char
      end
      i += 1
    end
    yield [:string, chars] if !chars.empty? && block_given?
  end

  def finished?
    return false unless @wait_thr

    ret = !@wait_thr.alive?
    if ret && !@exit_code
      @exit_code = @wait_thr.value
    end
    ret
  end

  def print_output!
    warn window_title.red
    warn @output
  end
end

class Multish
  def self.run!(args)
    self.new.run!(args)
  end

  def errored?
    @commands.any?(&:errored?)
  end

  def run!(args)
    @commands = args.each_with_index.map { |arg, index| MultishItem.new(arg, index, args.count) }
    Curses.init_screen
    Curses.start_color
    Curses.curs_set(0)
    Curses.init_pair(2, Curses::COLOR_WHITE, Curses::COLOR_GREEN)
    Curses.init_pair(3, Curses::COLOR_WHITE, Curses::COLOR_RED)
    Curses.init_pair(4, Curses::COLOR_WHITE, Curses::COLOR_BLACK)
    Curses.init_color(BRIGHT_WHITE, 1000, 1000, 1000)
    Curses.use_default_colors
    Curses.cbreak
    @commands.each(&:create_window!)
    @commands.each(&:open_process!)
    fdlist = @commands.flat_map(&:streams)
    begin
      while true
        fdlist.reject!(&:closed?)
        break if fdlist.empty?

        ready = IO.select(fdlist)[0]
        ready.each do |fd|
          @commands.each { |command| command.try_update(fd) }
        end
        @commands.each(&:update_title!)
        break if @commands.all?(&:finished?)
      end
    rescue StandardError => e
      Curses.close_screen
      warn 'INTERNAL ERROR'.red
      warn e.message
      warn e.backtrace
    ensure
      Curses.curs_set(1)
      Curses.close_screen
      if errored?
        warn 'At least one of the commands exited with error.'
        @commands.select(&:errored?).each(&:print_output!)
        exit 1
      else
        exit 0
      end
    end
  end
end
