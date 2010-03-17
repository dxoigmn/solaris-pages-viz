# Solaris Pages Viz

Solaris pages viz is a real-time visualization of the physical pages on your 
machine. It uses [mdb][1] and [dtrace][2] to fetch the necessary information, 
and then uses [processing][3] to to display this information.

Essentially, we are providing a visual view of something similar to the
following output from [mdb][1]:

    > ::memstat
    Page Summary                Pages                MB  %Tot
    ------------     ----------------  ----------------  ----
    Kernel                     124164               485   48%
    ZFS File Data                7800                30    3%
    Anon                        90072               351   35%
    Exec and libs                1257                 4    0%
    Page cache                   6352                24    2%
    Free (cachelist)             5776                22    2%
    Free (freelist)             24561                95    9%

    Total                      259982              1015
    Physical                   259981              1015

That is, we want to show each page of the different types (e.g., kernel, zfs,
anon, exec, etc.) in a different color. However, we want to also update this
visualization so we employ [dtrace][2] probes to keep the view updated.

![Solaris Pages Viz Screenshot](http://github.com/dxoigmn/solaris-pages-viz/blob/master/screenshot.png?raw=true)

## mdb

[mdb][1] is Solaris' modular debugger. It will suited to debugging the kernel in
real-time, thus we use it to fetch the physical pages from memory. In order to
do this, we a series of commands to get the necessary information.

First, we need to figure out the total number of pages, so we issue the
following:

    > total_pages /D
    total_pages:
    total_pages:    259981

Next, we need to figure out the addresses of some well known global vnodes,
particularly the [vnode][6] used for all segkmem related pages and the
[vnode][6] used for all zfs related pages. These addresses will allow use to the
compare [vnode][4] address to determine the type of [page][5] we are looking at.


    > ::nm ! grep kvp
    0xfffffffffbc2dd80|0x00000000000000c8|OBJT |GLOB |0x0  |15      |kvp
    > ::nm ! grep zvp
    0xfffffffffbc2dfa0|0x00000000000000c8|OBJT |GLOB |0x0  |15      |zvp

Finally, we need to extract all the pages. Luckily, mdb has a built in command
to do this, but we want to extract specific fields from each [page][5]:

    > ::walk page | ::print -n page_t p_pagenum p_vnode p_state p_vnode->v_flag
    p_pagenum = 0x27a8e
    p_vnode = 0xffffff00d2c85d80
    p_state = 0x10
    p_vnode->v_flag = 0x20040
    ...


## dtrace

[dtrace][2] is a dynamic tracing framework for Solaris. It allows to hook into a
bunch of probes and/or the entry or exit of functions. We use it to get
real-time paging information because it is costly to repeatedly query mdb for
changes to the physical pages.

Using [dtrace][2] require writing probes that hook into specific functions. In
particular, we hook two things: the entry into [fop\_pageio][7] and the
[pgin/pgout][8] counters in the [vminfo][8] provider. We hook the entry to
[fop\_pageio][7] simply to save the a pointer to the current [page][5]. Then, for
each pgin or pgout, we simply output the necessary fields from the [page][5] in
a manner similar to the output from [mdb][1] above. The script is:

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

Output looks similar to the output form [mdb][1] above to allow ease of parsing:

    p_pagenum = 0x32634
    p_vnode = 0xfffffffffbc2dd80
    p_state = 0
    p_vnode->v_flag = 0

## processing

Processing is a simply framework for drawing. Once we have all the necessary 
information, we use processing to visualize it. We first use the total number of
pages to determine the width and height of the window. We do this by simply
finding the factors of it and choosing the two that have minimal difference.
Because the total number of pages is relatively small, factoring this integer is
fast.

Then for every output, we parse the values and draw a pixel for each updated
page state. We map the colors in the following way:

  * Kernel - Blue
  * ZFS File Data - Fuchsia
  * Anon - Red
  * Exec and libs - Aqua
  * Page cache - Green
  * Free (cachelist) - Yellow
  * Free (freelist) - Black
  * Unknown - White

## dependencies

The following are dependencies:

  * [ruby][10]
  * [ruby-processing][9] 1.0.9 gem

If you have ruby and rubygems installed, it's as simply as:

    $ gem install ruby-processing

Then you should be able to run solaris\_pages\_viz.rb:

    $ ./solaris\_pages\_viz.rb


[1]: http://docs.sun.com/app/docs/doc/816-5041
[2]: http://www.sun.com/bigadmin/content/dtrace/index.jsp
[3]: http://processing.org/
[4]: http://src.opensolaris.org/source/xref/onnv/onnv-gate/usr/src/uts/common/sys/vnode.h#227
[5]: http://src.opensolaris.org/source/xref/onnv/onnv-gate/usr/src/uts/common/vm/page.h#463
[6]: http://src.opensolaris.org/source/xref/onnv/onnv-gate/usr/src/uts/common/sys/vnode.h#1342
[7]: http://src.opensolaris.org/source/xref/onnv/onnv-gate/usr/src/uts/common/fs/vnode.c#4037
[8]: http://wikis.sun.com/display/DTrace/vminfo+Provider
[9]: http://wiki.github.com/jashkenas/ruby-processing/
[10]: http://www.ruby-lang.org/