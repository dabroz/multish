require 'multish/version'

require 'curses'
require 'open3'

class MultishItem
  attr_reader :command

  def initialize(command, index, count)
    @command = command
    @index = index
    @count = count
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
    else
      4
    end
  end

  def errored?
    @exit_code && !(@exit_code == 0)
  end

  def update_title!
    @nav_window.setpos(0, 0)
    @nav_window.attron(Curses.color_pair(color_code) | Curses::A_REVERSE | Curses::A_BOLD)
    text = !finished? ? "$ #{command}" : "[ #{command} ] -> #{@exit_code}"
    @nav_window.addstr(text.ljust(width - 1))
    @nav_window.refresh
  end

  def open_process!
    @stdin, @stdout, @stderr, @wait_thr = Open3.popen3(@command)
    @stdin.close
  end

  def streams
    [@stdout, @stderr]
  end

  def try_update(fd)
    return unless fd == @stdout || fd == @stderr
    line = fd.gets
    print(line) if line
  end

  def print(text)
    @window.addstr(text)
    @window.refresh
  end

  def finished?
    return false unless @wait_thr
    ret = !@wait_thr.alive?
    if ret && !@exit_code
      @exit_code = @wait_thr.value
    end
    ret
  end
end

class Multish
  def self.run!(args)
    self.new.run!(args)
  end

  def run!(args)
    @commands = args.each_with_index.map { |arg, index| MultishItem.new(arg, index, args.count) }
    Curses.init_screen
    Curses.start_color
    Curses.curs_set(0)
    Curses.init_pair(2, Curses::COLOR_WHITE, Curses::COLOR_GREEN)
    Curses.init_pair(3, Curses::COLOR_WHITE, Curses::COLOR_RED)
    Curses.init_pair(4, Curses::COLOR_WHITE, Curses::COLOR_BLACK)
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
    ensure
      Curses.curs_set(1)
      Curses.close_screen
      exit(@commands.any?(&:errored?) ? 1 : 0)
    end
  end
end
