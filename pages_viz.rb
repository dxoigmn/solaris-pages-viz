#!/usr/bin/env ruby

class PagesViz < Processing::App
  def setup
    # Setup
    setup_mdb
    setup_dtrace

    # Start threads
    Thread.new { run_mdb }
    Thread.new { run_dtrace }
  end

  def setup_mdb
    # Setup mdb
    $stdout.puts "[mdb] Opening process..."
    @mdb = IO.popen("pfexec mdb -k", "w+")

    $stdout.print "[mdb] Reading total_pages..."
    $stdout.flush
    @mdb << "total_pages /D\n"
    @mdb.readline # Skip first line
    total_pages = @mdb.readline.chomp.gsub(/total_pages:\s+/, "").to_i
    $stdout.puts total_pages

    $stdout.print "[mdb] Reading kvp..."
    $stdout.flush
    @mdb << "::nm ! grep kvp\n"
    @kvp = @mdb.readline.chomp.gsub(/\|.*/, "").to_i(16)
    $stdout.puts "0x#{@kvp.to_s(16)}"

    $stdout.print "[mdb] Reading zvp..."
    $stdout.flush
    @mdb << "::nm ! grep zvp\n"
    @zvp = @mdb.readline.chomp.gsub(/\|.*/, "").to_i(16)
    $stdout.puts "0x#{@zvp.to_s(16)}"

    # Find factors of total_pages for display width/height
    factor = 1

    for i in (2..(0.5 + Math.sqrt(total_pages)).to_i)
      factor = i if (total_pages % i == 0) and ((total_pages/i - i) < (total_pages/factor - factor))
    end

    # Width is the longer factor
    @width   = [factor, total_pages/factor].max
    @height  = [factor, total_pages/factor].min

    # Setup default canvas
    size @width, @height
    background 255, 255, 255
  end

  def run_mdb
    # Initial state
    pagenum = nil
    vnode   = nil
    state   = nil
    vflag   = nil

    $stdout.puts "[mdb] Reading pages..."
    @mdb << "::walk page | ::print -n page_t p_pagenum p_vnode p_state p_vnode->v_flag\n"
    until @mdb.eof?
      line = @mdb.readline.chomp

      #$stdout.puts "[mdb] #{line}"

      if line =~ /p_vnode = /
        vnode = line.gsub(/p_vnode = /, "").to_i(16)
        next
      end

      if line =~ /p_state = /
        state = line.gsub(/p_state = /, "").to_i(16)
        next
      end

      if line =~ /p_vnode->v_flag = /
        vflag = line.gsub(/p_vnode->v_flag = /, "").to_i(16)
        next
      end

      # Skip and other unknown text
      next unless line =~ /p_pagenum = /

      # If we have a full info about a page, determine it's color
      if pagenum
        c = color 255, 255, 255       # Free-free (3)

        if vnode == @kvp              # Kernel (1)
          c = color 0, 0, 255

        elsif vnode == @zvp           # ZFS (6)
          c = color 128, 0, 128

        elsif (state & 0x80) != 0     # Free-cache (5)
          c = color 128, 128, 0

        elsif (vflag & 0x20000) != 0  # Anon (2)
          c = color 255, 0, 0

        elsif (vflag & 0x1000) != 0   # Exec (7)
          c = color 0, 128, 128

        elsif vnode =~ /0x.*/         # VNode (4)
          c = color 0, 255, 0

        end

        # Calculate x, y coordinates from pagenum
        x = pagenum % @width
        y = (pagenum / @width.to_f).ceil

        update_page x, y, c
      end

      # Save pagenum
      pagenum = line.gsub(/p_pagenum \= /, "").to_i(16)

      # Reset state, since this is a new record
      vnode   = nil
      state   = nil
      vflag   = nil
    end
  end
  
  def setup_dtrace
    $stdout.puts "[dtrace] Opening process..."
    @dtrace = IO.popen("pfexec dtrace -s /dev/stdin", "w+")
  end

  def run_dtrace
    # Initial state
    pagenum = nil
    vnode   = nil
    state   = nil
    vflag   = nil

    @dtrace << DATA.readlines
    @dtrace.close_write

    until @dtrace.eof?
      line = @dtrace.readline.chomp

      #$stdout.puts "[dtrace] #{line}"

      if line =~ /p_vnode = /
        vnode = line.gsub(/p_vnode = /, "").to_i(16)
        next
      end

      if line =~ /p_state = /
        state = line.gsub(/p_state = /, "").to_i(16)
        next
      end

      if line =~ /p_vnode->v_flag = /
        vflag = line.gsub(/p_vnode->v_flag = /, "").to_i(16)
        next
      end

      # Skip and other unknown text
      next unless line =~ /p_pagenum = /

      # If we have a full info about a page, determine it's color
      if pagenum
        c = color 255, 255, 255       # Free-free (3)

        if vnode == @kvp              # Kernel (1)
          c = color 0, 0, 255

        elsif vnode == @zvp           # ZFS (6)
          c = color 128, 0, 128

        elsif (state & 0x80) != 0     # Free-cache (5)
          c = color 128, 128, 0

        elsif (vflag & 0x20000) != 0  # Anon (2)
          c = color 255, 0, 0

        elsif (vflag & 0x1000) != 0   # Exec (7)
          c = color 0, 128, 128

        elsif vnode =~ /0x.*/         # VNode (4)
          c = color 0, 255, 0

        end

        # Calculate x, y coordinates from pagenum
        x = pagenum % @width
        y = (pagenum / @width.to_f).ceil

        update_page x, y, c
      end

      # Save pagenum
      pagenum = line.gsub(/p_pagenum \= /, "").to_i(16)

      # Reset state, since this is a new record
      vnode   = nil
      state   = nil
      vflag   = nil
    end
  end

  def update_page(x, y, c)
    set x, y, c
  end

  def draw
    # !!! DO NOT REMOVE ME !!!
  end
end

PagesViz.new :title => "PagesViz"

__END__
#pragma D option quiet

fbt::fop_pageio:entry
{
  self->pp = args[1];
}

vminfo:::pgin,
vminfo:::pgout
{
  printf("p_pagenum = 0x%x\n", self->pp->p_pagenum);
  printf("p_vnode = 0x%p\n", self->pp->p_vnode);
  printf("p_state = 0x%x\n", self->pp->p_state);
  printf("p_vnode->v_flag = 0x%x\n", self->pp->p_vnode->v_flag);
}
