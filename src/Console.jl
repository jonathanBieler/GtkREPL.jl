mutable struct Console{T<:GtkTextView,B<:GtkTextBuffer} <: GtkScrolledWindow

    handle::Ptr{Gtk.GObject}
    view::T
    buffer::B
    run_task::Task
    prompt_position::Integer
    prompt::String
    stdout_buffer::IOBuffer
    worker::TCPSocket
    worker_port::Int
    worker_idx::Int
    history::HistoryProvider
    run_task_start_time::AbstractFloat
    main_window
    eval_in::Module
    mode::REPLMode

    function Console{T,B}(w_idx::Int, main_window, worker::TCPSocket,
        init_fun=init_view_buffer!,b_args=()) where {T<:GtkTextView,B<:GtkTextBuffer}

        b = B(b_args...)
        v = T(b)

        prompt = "Main>"
        set_gtk_property!(b,:text,prompt)

        init_fun(v,b)

        sc = GtkScrolledWindow()
        set_gtk_property!(sc,:hscrollbar_policy,1)
        push!(sc,v)

        t = @async begin end
        history = setup_history(w_idx)
        worker = worker == nothing ? w_idx : worker

        n = new(sc.handle,v,b,t,length(prompt)+1,prompt,IOBuffer(),worker,0,w_idx,
            history,time(),main_window,Main,NormalMode()
        )
        Gtk.gobject_move_ref(n, sc)
    end
end
Console(w_idx::Int, main_window, worker::TCPSocket) = Console{GtkTextView,GtkTextBuffer}(w_idx, main_window, worker)

function init_view_buffer!(v,b)
    set_gtk_property!(v,:margin_bottom,10)
    set_gtk_property!(v,:margin_left,4)
end

console_manager(c::Console) = console_manager(c.main_window)
worker(c::Console) = c.worker_idx == 1 ? c.worker_idx : c.worker

import Base.write
function write(c::Console,str::AbstractString)
    insert!(c.buffer,end_iter(c.buffer),str)
    text_buffer_place_cursor(c.buffer,end_iter(c.buffer))
end

function switch_mode(c::Console,mode::REPLMode)
    previous_prompt = prompt(c)
    c.mode=mode
    switch_prompt(c,mode,previous_prompt)
end

function check_switch_mode(c::Console,event)
    for mode in REPLModes
        if doing(switch_key(mode),event)
            switch_mode(c,mode)
            return true
        end
    end
    false
end

function switch_prompt(c::Console,mode::REPLMode,previous_prompt::String)

    its = GtkTextIter(c.buffer,c.prompt_position-length(previous_prompt))
    ite = GtkTextIter(c.buffer,c.prompt_position)
    replace_text(c.buffer,its,ite, prompt(c))

    diff = length(prompt(c))-length(previous_prompt)
    c.prompt_position += diff
end

prompt(c::Console) = prompt(c,c.mode)

function write_before_prompt(c::Console,str::AbstractString)

    it = GtkTextIter(c.buffer,c.prompt_position-length(prompt(c)))
    insert!(c.buffer, it,str)
    c.prompt_position += length(str)

    it = GtkTextIter(c.buffer,c.prompt_position-length(prompt(c)))
    if get_text_left_of_iter(it) != "\n"
        insert!(c.buffer,it,"\n")
        c.prompt_position += 1
    end
end

function new_prompt(c::Console)
    insert!(c.buffer,end_iter(c.buffer),"\n$(prompt(c))")
    c.prompt_position = length(c.buffer)+1
    text_buffer_place_cursor(c.buffer,end_iter(c.buffer))
end

function clear(c::Console)
    set_gtk_property!(c.buffer,:text,"")
end

##
function check_worker(c::Console)
    c.worker_idx == 1 && return true
    s = worker(c)
    if s.status < Sockets.StatusConnecting
        @info "worker not connect, try to reconnect on port $(c.worker_port)"
        try 
            c.worker = connect(c.worker_port)
        catch err
            @warn err
            return false
        end
    end
    return true
end

function on_return(c::Console,cmd::AbstractString)

    cmd = string(strip(cmd))#avoid getting a substring
    buffer = c.buffer

    write(c,"\n")
    if !check_worker(c) 
        write(c,"Couldn't connect to worker\n")
        return
    end

    push!(c.history,cmd)
    seek_end(c.history)

    found = false
    if c.mode == NormalMode()
        (found,t) = check_console_commands(cmd,c)
    end

    if !found
        on_return(c,c.mode,cmd)
    else
        c.run_task = t
    end

    c.run_task_start_time = time()
    GtkExtensions.text(c.main_window.statusBar,"Busy")

    g_timeout_add(50,write_output_to_console,(c,found))
    nothing
end

function kill_current_task(c::Console)
    try #otherwise this makes the callback fail in some versions
        #@async Base.throwto(c.run_task, InterruptException())
        !isdone(c) && interrupt_task(c)
    catch
    end
end

interrupt_task(c::Console) = remotecall_fetch(RemoteGtkREPL.interrupt_task,worker(c))
isdone(c::Console) = remotecall_fetch(RemoteGtkREPL.isdone,worker(c))
#isdone(c::Console) = remotecall_fetch(include_string, worker(c), Main,"RemoteGtkREPL.isdone()")

"Wait for the running task to end and print the result in the console.
Run from Gtk main loop."
function write_output_to_console(user_data)

    c, is_console_command = unsafe_pointer_to_objref(user_data)

    if is_console_command
        t = c.run_task
        !istaskdone(t) && return Cint(true)
    else
        # if a worker is busy computing things it will block here
        # so I just check for a short duration if it's done
        isdone_t = @async isdone(c)
        start = time()
        while (isdone_t.state != :done) && ((time()-start) < 0.01)
            sleep(0.001)
        end
        isdone_t.state != :done && return Cint(true)
        isdone_t.result == false && return Cint(true)

        #!isdone(c) && return Cint(true)
        t = remotecall_fetch(run_task,worker(c))
        if typeof(t) != Task
            c.worker = connect(c.worker_port)
            t = remotecall_fetch(run_task,worker(c))
        end
    end

    try
        if t.result != nothing

            if typeof(t.result) <: Tuple #console commands can return just a string
                str, v = t.result
            else
                str, v = (t.result, nothing)
            end

            if @eval isdefined(:Gadfly) 
                typeof(v) <: Gadfly.Plot && display(v)
            end
                
            finalOutput = str == nothing ? "" : str

            if str == InterruptException()
                finalOutput = string(str) * "\n"
            end

            write(c,finalOutput)
        end
        new_prompt(c)
    catch other_err
        write(c,sprint(showerror,other_err))
        new_prompt(c)
    end
    on_command_done(c.main_window)

    t = @sprintf("%4.6f",time()-c.run_task_start_time)
    GtkExtensions.text(c.main_window.statusBar,"Run time $(t)s")

    return Cint(false)
end

"Get the text after the prompt"
function command(c::Console)
    its = GtkTextIter(c.buffer,c.prompt_position)
    ite = GtkTextIter(c.buffer,length(c.buffer)+1)
    cmd = text_iter_get_text(its,ite)
    return cmd
end
function command(c::Console,str::AbstractString,offset::Integer)

    its = GtkTextIter(c.buffer,c.prompt_position)
    ite = GtkTextIter(c.buffer,length(c.buffer)+1)
    replace_text(c.buffer,its,ite, str)
    if offset >= 0 && c.prompt_position+offset-1 <= length(c.buffer)
        text_buffer_place_cursor(c.buffer,c.prompt_position+offset-1)
    end
end
command(c::Console,str::AbstractString) = command(c,str,-1)

function move_cursor_to_end(c::Console)
    text_buffer_place_cursor(c.buffer,end_iter(c.buffer))
end
function move_cursor_to_prompt(c::Console)
    text_buffer_place_cursor(c.buffer,c.prompt_position-1)
end

"return cursor position in the prompt text"
function cursor_position(c::Console)
    a = c.prompt_position
    b = cursor_position(c.buffer)
    b-a+1
end
cursor_position(b::GtkTextBuffer) = get_gtk_property(b,:cursor_position,Int)

function select_on_ctrl_shift(direction,c::Console)

    buffer = c.buffer
    (found,its,ite) = selection_bounds(buffer)

    if direction == :start
        ite,its = its,ite
    end

    its = found ? nonmutable(buffer,its) : get_text_iter_at_cursor(buffer)

    direction == :start && move_cursor_to_prompt(c)
    direction == :end && move_cursor_to_sentence_end(buffer)

    ite = get_text_iter_at_cursor(buffer)
    selection_bounds(buffer,ite,its)#invert here so the cursor end up on the far right
end

##
ismodkey(event::Gtk.GdkEvent,mod::Integer) =
    any(x -> x == event.keyval,[
        Gtk.GdkKeySyms.Control_L, Gtk.GdkKeySyms.Control_R,
        Gtk.GdkKeySyms.Meta_L,Gtk.GdkKeySyms.Meta_R,
        Gtk.GdkKeySyms.Hyper_L,Gtk.GdkKeySyms.Hyper_R,
        Gtk.GdkKeySyms.Shift_L,Gtk.GdkKeySyms.Shift_R
    ]) ||
    any(x -> x == event.state & mod,[
        GdkModifierType.CONTROL,Gtk.GdkKeySyms.Meta_L,Gtk.GdkKeySyms.Meta_R,
        PrimaryModifier, SHIFT, GdkModifierType.GDK_MOD1_MASK,
        SecondaryModifer, PrimaryModifier+SHIFT, PrimaryModifier+GdkModifierType.META])


before_prompt(console,pos::Integer) = pos+1 < console.prompt_position
before_prompt(console) = before_prompt(console,get_gtk_property(console.buffer,:cursor_position,Int) )

before_or_at_prompt(console,pos::Integer) = pos+1 <= console.prompt_position
before_or_at_prompt(console) = before_or_at_prompt(console,get_gtk_property(console.buffer,:cursor_position,Int))
at_prompt(console,pos::Integer) = pos+1 == console.prompt_position

function iters_at_console_prompt(console)
    its = GtkTextIter(console.buffer,console.prompt_position)
    ite = nonmutable(console.buffer, end_iter(console.buffer) )
    (its,ite)
end

#FIXME disable drag and drop text above cursor
@guarded (PROPAGATE) function console_key_press_cb(widgetptr::Ptr, eventptr::Ptr, user_data)

    textview = convert(GtkTextView, widgetptr)
    event = convert(Gtk.GdkEvent, eventptr)
    console = user_data
    buffer = console.buffer

    cmd = command(console)
    pos = cursor_position(console)
    prefix = length(cmd) >= pos ? cmd[1:pos] : ""

    mod = get_default_mod_mask()

    #put back the cursor after the prompt
    if before_prompt(console)
        #check that we are not trying to copy or something of the sort
        if !ismodkey(event,mod)
            move_cursor_to_end(console)
        end
    end

    if length(cmd) == 0
        check_switch_mode(console,event) && return INTERRUPT
    end

    (found,it_start,it_end) = selection_bounds(buffer)

    #prevent deleting text before prompt
    if event.keyval == Gtk.GdkKeySyms.BackSpace ||
       event.keyval == Gtk.GdkKeySyms.Delete ||
       event.keyval == Gtk.GdkKeySyms.Clear ||
       doing(Actions["cut"],event)

        if found
            before_prompt(console,offset(it_start)) && return INTERRUPT
        else
            before_or_at_prompt(console) && return INTERRUPT
        end
    end
    if doing(Actions["move_to_line_start"],event) ||
        doing(Action(GdkKeySyms.Left, PrimaryModifier),event)
        move_cursor_to_prompt(console)
        return INTERRUPT
    end
    if doing(Actions["move_to_line_end"],event) ||
       doing(Action(GdkKeySyms.Right, PrimaryModifier),event)
        move_cursor_to_end(console)
        return INTERRUPT
    end
    if doing(Actions["clear_console"],event)
        clear(console)
        new_prompt(console)
        return INTERRUPT
    end
    if doing(Action(GdkKeySyms.Right, PrimaryModifier+GdkModifierType.SHIFT),event)
        select_on_ctrl_shift(:end,console)
        return INTERRUPT
    end
    if doing(Action(GdkKeySyms.Left, PrimaryModifier+GdkModifierType.SHIFT),event)
        select_on_ctrl_shift(:start,console)
        return INTERRUPT
    end

    if doing(Action(GdkKeySyms.Left, NoModifier),event)
        if found
            at_prompt(console,offset(it_start)) && return INTERRUPT
        else
            before_or_at_prompt(console) && return INTERRUPT
        end
        return PROPAGATE
    end
    if doing(Action(GdkKeySyms.Left, GdkModifierType.SHIFT),event)

        at_prompt(console,offset(it_start)) && return INTERRUPT

        return PROPAGATE
    end

    if event.keyval == Gtk.GdkKeySyms.Up
        if found
            if !before_prompt(console,offset(it_start))
                selection_bounds(buffer,GtkTextIter(buffer,console.prompt_position),nonmutable(buffer,it_end))
                return INTERRUPT
            end
            return PROPAGATE
        end
        !history_up(console.history,prefix,cmd) && return convert(Cint,true)
        command(console,history_get_current(console.history),length(prefix))
        return INTERRUPT
    end

    if event.keyval == Gtk.GdkKeySyms.Down
        hasselection(buffer) && return PROPAGATE
        history_down(console.history,prefix,cmd)
        command(console, history_get_current(console.history),length(prefix))

        return INTERRUPT
    end
    if event.keyval == Gtk.GdkKeySyms.Tab
        #convert cursor position into index
        autocomplete(console,cmd,pos)
        return INTERRUPT
    end
    if doing(Actions["select_all"],event)
        #select all
        before_prompt(console) && return PROPAGATE
        #select only prompt
        its,ite = iters_at_console_prompt(console)
        selection_bounds(buffer,its,ite)
        return INTERRUPT
    end
    if doing(Actions["interrupt_run"],event)
        kill_current_task(console)
        return INTERRUPT
    end
    if doing(Actions["copy"],event)
        auto_select_prompt(found, console, buffer)
        signal_emit(textview, "copy-clipboard", Nothing)
        return INTERRUPT
    end
    if doing(Actions["paste"],event)
        signal_emit(textview, "paste-clipboard", Nothing)
        return INTERRUPT
    end
    if doing(Actions["cut"],event)
        auto_select_prompt(found, console, buffer)
        signal_emit(textview, "cut-clipboard", Nothing)
        return INTERRUPT
    end

    return PROPAGATE
end

"""
Auto select the prompt text when nothing is selected
and we are trying to copy or cut.
"""
function auto_select_prompt(found, console, buffer)
    if !found && !before_prompt(console)
        its,ite = iters_at_console_prompt(console)
        selection_bounds(buffer,its,ite)
    end
end

function _callback_only_for_return(widgetptr::Ptr, eventptr::Ptr, user_data)

    event = convert(Gtk.GdkEvent, eventptr)
    console = user_data
    buffer = console.buffer

    cmd = command(console)

    if event.keyval == Gtk.GdkKeySyms.Return

        if console.run_task.state == :done || console.run_task.state == :failed
            on_return(console,cmd)
        end
        return Cint(true)
    end
    return Cint(false)
end
cfunction(_callback_only_for_return, Cint, (Ptr{Console},Ptr{Gtk.GdkEvent},Console))

## MOUSE CLICKS

@guarded (INTERRUPT) function _console_button_press_cb(widgetptr::Ptr, eventptr::Ptr, user_data)

    textview = convert(GtkTextView, widgetptr)
    event = convert(Gtk.GdkEvent, eventptr)
    buffer = get_gtk_property(textview,:buffer,GtkTextBuffer)
    console = user_data
    main_window = console.main_window

    if event.event_type == Gtk.GdkEventType.DOUBLE_BUTTON_PRESS
        select_word_double_click(textview,buffer,Int(event.x),Int(event.y))
        return INTERRUPT
    end

    mod = get_default_mod_mask()
    if Int(event.button) == 1 && Int(event.state & mod) == Int(PrimaryModifier)
        open_method(textview) && return INTERRUPT
    end

    if rightclick(event)
        menu = buildmenu([
            MenuItem("Close Console",remove_console_cb),
            MenuItem("Add Console",add_console_cb),
            MenuItem("Clear Console",clear_console_cb),
            MenuItem("Toggle Wrap Mode",toggle_wrap_mode_cb)
            #GtkSeparatorMenuItem,
            #MenuItem("Toggle Wrap Mode",kill_current_task_cb),
            ],
            (console_manager(main_window), console, main_window)
        )
        popup(menu,event)
        return INTERRUPT
    end

    return PROPAGATE
end

global const console_mousepos = zeros(Int,2)
global const console_mousepos_root = zeros(Int,2)

#FIXME replace this by the same thing at the window level ?
#or put this as a field of the type.
@guarded (PROPAGATE) function console_motion_notify_event_cb(widget::Ptr,  eventptr::Ptr, user_data)
    event = convert(Gtk.GdkEvent, eventptr)

    console_mousepos[1] = round(Int,event.x)
    console_mousepos[2] = round(Int,event.y)
    console_mousepos_root[1] = round(Int,event.x_root)
    console_mousepos_root[2] = round(Int,event.y_root)
    return PROPAGATE
end

##

## auto-scroll the textview
function console_scroll_cb(widgetptr::Ptr, rectptr::Ptr, user_data)

    c = user_data
    adj = get_gtk_property(c,:vadjustment, GtkAdjustment)
    set_gtk_property!(adj,:value,
        get_gtk_property(adj,:upper,AbstractFloat) -
        get_gtk_property(adj,:page_size,AbstractFloat)
    )
    adj = get_gtk_property(c,:hadjustment, GtkAdjustment)
    set_gtk_property!(adj,:value,0)

    nothing
end

## Auto-complete

function complete_additional_symbols(str,S)
    comp = Array{String}(undef, 0)
    for s in S
        startswith(s,str) && push!(comp,s)
    end
    comp
end

# TODO use the same code than in the editor
function autocomplete(c::Console,cmd::AbstractString,pos::Integer)

    isempty(cmd) && return
    pos > length(cmd) && return

    scmd = JuliaWordsUtils.CharArray(cmd)

    (ctx, m) = console_commands_context(cmd)

    if c.mode == ShellMode()
        ctx, m = :file, nothing
    end

    lastpart = pos < length(scmd) ? scmd[pos+1:end] : ""
    cmd = scmd[1:pos]

    if ctx == :normal
        isempty(cmd) && return
        comp,dotpos = completions_in_module(cmd,c)
    end
    if ctx == :file
        (comp,dotpos) = remotecall_fetch(Base.REPL.shell_completions,worker(c),cmd, lastindex(cmd))
        comp = REPL.completion_text.(comp)
    end

    update_completions(c,comp,dotpos,cmd,lastpart)
end

function completions_in_module(cmd,c::Console)
    prefix = string(c.eval_in,".")
    comp,dotpos = remotecall_fetch(completions, worker(c), prefix * cmd, lastindex(prefix * cmd))
    dotpos -= lastindex(prefix)
    comp = REPL.completion_text.(comp)
    comp,dotpos
end

##

# cmd is the word, including dots we are trying to complete
function update_completions(c::Console,comp,dotpos,cmd,lastpart)

    isempty(comp) && return

    dotpos = dotpos.start
    prefix = dotpos > 1 ? cmd[1:dotpos-1] : ""

    if(length(comp)>1)

        maxLength = maximum(map(length,comp))
        w = width(c.view)
        nchar_to_width(x) = 0.9*x*fontsize #TODO pango_font_metrics_get_approximate_char_width
        n_per_line = max(1,round(Int,w/nchar_to_width(maxLength)))

        out = "\n"
        for i = 1:length(comp)
            spacing = repeat(" ",maxLength-length(comp[i]))
            out = "$out $(comp[i]) $spacing"
            if mod(i,n_per_line) == 0
                out = out * "\n"
            end
        end

        write_before_prompt(c,out)
        out = prefix * Base.LineEdit.common_prefix(comp)
    else
        out = prefix * comp[1]
    end

    offset = length(out)#place the cursor after the newly inserted piece
    #update entry
    out = out * lastpart
    #out = remove_filename_from_methods_def(out)

    command(c,out,offset)
end

function init!(c::Console)
    signal_connect(console_key_press_cb, c.view, "key-press-event",
    Cint, (Ptr{Gtk.GdkEvent},), false, c)
    signal_connect(_callback_only_for_return, c.view, "key-press-event",
    Cint, (Ptr{Gtk.GdkEvent},), false,c)
    signal_connect(_console_button_press_cb,c.view, "button-press-event",
    Cint, (Ptr{Gtk.GdkEvent},),false,c)
    signal_connect(console_motion_notify_event_cb,c, "motion-notify-event",
    Cint, (Ptr{Gtk.GdkEvent},), false)
    signal_connect(console_scroll_cb, c.view, "size-allocate", Nothing,
    (Ptr{Gtk.GdkRectangle},), false,c)

    # Note that due to historical reasons, GtkNotebook refuses to switch to a page unless the child widget is visible.
    # Therefore, it is recommended to show child widgets before adding them to a notebook.
    show(c)
    push!(console_manager(c),c)
    set_tab_label_text(console_manager(c),c,"C" * string(length(console_manager(c))))
    g_timeout_add(100,print_to_console,c)
end

"Run from the main Gtk loop, and print to console
the content of stdout_buffer"
function print_to_console(user_data)

    console = unsafe_pointer_to_objref(user_data)

    s = String(take!(console.stdout_buffer))
    if !isempty(s)
        s = translate_colors(s)
        write(console,s)
    end
    if is_running
        return Cint(true)
    else
        return Cint(false)
    end
end
#cfunction(print_to_console, Cint, Ptr{Console})

#FIXME dirty hack?
function translate_colors(s::AbstractString)

    s = replace(s,"\e[1m\e[31m" => "* ")
    s = replace(s,"\e[1m\e[32m" => "* ")
    s = replace(s,"\e[1m\e[31" => "* ")
    s = replace(s,"\e[0m" => "")
    s
end

@guarded (nothing) function toggle_wrap_mode_cb(btn::Ptr, user_data)
    ntbook, tab, main_window = user_data
    tab.view.wrap_mode[Int] = !Bool(tab.view.wrap_mode[Int])
    nothing
end
@guarded (nothing) function clear_console_cb(btn::Ptr, user_data)
    ntbook, tab, main_window = user_data
    clear(tab)
    new_prompt(tab)
    nothing
end
@guarded (nothing) function kill_current_task_cb(btn::Ptr, user_data)
    ntbook, tab, main_window = user_data
    kill_current_task(tab)
    nothing
end
@guarded (nothing) function add_console_cb(btn::Ptr, user_data)
    ntbook, tab, main_window = user_data
    #add_console(main_window)
    add_remote_console(main_window,GtkREPL)
    nothing
end
@guarded (nothing) function remove_console_cb(btn::Ptr, user_data)
    ntbook, tab, main_window = user_data
    idx = index(ntbook,tab)
    if idx != 1#can't close the main console
        c = ntbook[idx]
        remotecall_fetch(info,worker(c),"Goodbye.")
        splice!(ntbook,idx)
        set_current_page_idx(ntbook,max(idx-1,0))
        #rmprocs(tab.worker_idx) # FIXME
    end
    nothing
end

get_current_console(console_mng::GtkNotebook) = console_mng[index(console_mng)]

#this is called by remote workers
function print_to_console_remote(s,idx::Integer)

    #copy the output to the right console buffer
    for i = 1:length(main_window.console_manager)
        c = get_tab(main_window.console_manager,i)

        if c.worker_idx == idx
            write(c.stdout_buffer,s)
        end
    end
end

## REDIRECT_STDOUT for main console

function send_stream(rd::IO, stdout_buffer::IO)
    nb = bytesavailable(rd)
    if nb > 0
        d = read(rd, nb)
        s = String(copy(d))

        if !isempty(s)
            write(stdout_buffer,s)
        end
    end
end

function watch_stream(rd::IO, c::Console)
    while !eof(rd) && is_running # blocks until something is available
        send_stream(rd,c.stdout_buffer)
        sleep(0.01) # a little delay to accumulate output
    end
end


#
