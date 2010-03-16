class PagesViz < Processing::App
  def setup
    # Read total_pages from mdb
    #lines = mdb "total_pages /D"
    #total_pages = lines[1].chomp.gsub(/total_pages:\s+/, "").to_i
    total_pages = 259981

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

    # Spin up reader thread
    start_reader_thread
  end

  def start_reader_thread
    Thread.new do
      # Initial state
      pagenum = nil
      vnode   = nil
      state   = nil
      vflag   = nil

      # Read pages from $stdin
      until $stdin.eof?
        line = $stdin.readline.chomp

        if line =~ /p_vnode = /
          vnode = line.gsub(/p_vnode = /, "")
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

          if vnode == "kvp"             # Kernel (1)
            c = color 102, 204, 255

          elsif vnode == "zvp"          # ZFS (6)
            c = color 255, 102, 102

          elsif (state & 0x80) != 0     # Free-cache (5)
            c = color 255, 111, 207

          elsif (vflag & 0x20000) != 0  # Anon (2)
            c = color 255, 204, 102

          elsif (vflag & 0x1000) != 0   # Exec (7)
            c = color 102, 255, 102

          elsif vnode =~ /0x.*/         # VNode (4)
            c = color 204, 102, 255

          elsif vnode == "trashvp"      # Trash (8)
            c = color 0, 0, 0

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
  end

  def update_page(x, y, c)
    set x, y, c
  end
end

PagesViz.new :title => "PagesViz"