require 'multish/version'

require 'curses'
require 'open3'
require 'colorize'

BRIGHT_WHITE = 15

$log = []

class Window
  def initialize(height, width, top, left)
    @window = Curses::Window.new(height, width, top, left)
    @fgcolor = :black
    @bgcolor = :bright_white
    reset!
  end

  def self.screen_width
    Curses.cols
  end

  def self.screen_height
    Curses.lines
  end

  def setpos(x, y)
    @window.setpos(x, y)
  end

  def bold=(value)
    if value
      @window.attron(Curses::A_BOLD)
    else
      @window.attroff(Curses::A_BOLD)
    end
  end

  def fgcolor=(value)
    @fgcolor = value
    update_color!
  end

  def bgcolor=(value)
    @bgcolor = value
    update_color!
  end

  def update_color!
    fgcode = get_code(@fgcolor)
    bgcode = get_code(@bgcolor)
    code = Window.create_color_pair(fgcode, bgcode)
    @window.attron(Curses.color_pair(code))
  end

  def get_code(color)
    case color
    when :black
      Curses::COLOR_BLACK
    when :red
      Curses::COLOR_RED
    when :green
      Curses::COLOR_GREEN
    when :yellow
      Curses::COLOR_YELLOW
    when :blue
      Curses::COLOR_BLUE
    when :magenta
      Curses::COLOR_MAGENTA
    when :cyan
      Curses::COLOR_CYAN
    when :white
      Curses::COLOR_WHITE
    when :bright_white
      Window.create_color(:bright_white, 1000, 1000, 1000)
    end
  end

  def self.create_color(code, r, g, b)
    @colors ||= {}
    new_index = 15 + @colors.count
    @colors[code] ||= [new_index, Curses.init_color(new_index, r, g, b)]
    @colors[code][0]
  end

  def self.create_color_pair(fg, bg)
    index = "#{fg}/#{bg}"
    @pairs ||= {}
    new_index = 100 + @pairs.count
    @pairs[index] ||= [new_index, Curses.init_pair(new_index, fg, bg)]
    @pairs[index][0]
  end

  def <<(str)
    @window.addstr(str)
  end

  def scrollok(value)
    @window.scrollok(value)
  end

  def refresh!
    @window.refresh
  end

  def reset!
    self.fgcolor = :black
    self.bgcolor = :bright_white
    self.bold = false
  end
end

class MultishItem
  attr_reader :command

  def initialize(command, index, count)
    @command = command
    @index = index
    @count = count
    @output = ''
  end

  def width
    (Window.screen_width / @count).floor
  end

  def height
    Window.screen_height
  end

  def left
    width * @index
  end

  def top
    0
  end

  def create_window!
    @nav_window = Window.new(1, width - 1, top, left)
    @window = Window.new(height - 1, width - 1, top + 1, left)
    @window.scrollok(true)
    update_title!
  end

  def color_code
    if !@wait_thr
      :yellow
    elsif finished?
      errored? ? :red : :green
    else # rubocop:disable Lint/DuplicateBranch
      :yellow
    end
  end

  def errored?
    @exit_code && @exit_code != 0
  end

  def update_title!
    @nav_window.setpos(0, 0)
    @nav_window.fgcolor = color_code
    @nav_window.bgcolor = :black
    @nav_window.bold = true
    @nav_window << window_title.ljust(width - 1)
    @nav_window.refresh!
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

  def try_update(fd)
    return unless [@stdout, @stderr].include?(fd)

    line = fd.gets
    print(line) if line
  end

  def print(text)
    @output << text
    color_print(@window, text)
    @window.refresh!
  end

  def color_print(window, input)
    parse_commands(input) do |op, arg|
      case op
      when :string
        window << arg
      when :reset
        window.reset!
      when :bold
        window.bold = true
      when :color
        window.fgcolor = arg
      when :error
        raise "ERROR: #{arg}"
      end
    end
  end

  COLORS = %i[black red green yellow blue magenta cyan white].freeze

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
              color = COLORS[subarg - 30]
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
      warn $log.join("\n").blue
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
