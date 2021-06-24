mutable struct Console{T<:GtkTextView, B<:GtkTextBuffer} <: GtkScrolledWindow

    handle::Ptr{Gtk.GObject}
    view::T
    buffer::B
    prompt_position::Integer
    prompt::String
    stdout_buffer::IOBuffer
    worker::TCPSocket
    worker_port::Int
    worker_idx::Int
    busy::Bool
    history::HistoryProvider
    main_window
    eval_in::Module
    mode::REPLMode

    function Console{T, B}(w_idx::Int, main_window, worker::TCPSocket,
        init_fun=init_view_buffer!, b_args=()) where {T<:GtkTextView, B<:GtkTextBuffer}

        b = B(b_args...)
        v = T(b)

        prompt = "Main>"
        set_gtk_property!(b, :text, prompt)

        init_fun(v, b)

        sc = GtkScrolledWindow()
        set_gtk_property!(sc, :hscrollbar_policy, 1)
        push!(sc, v)

        history = setup_history(w_idx)
        worker = isnothing(worker) ? w_idx : worker

        n = new(sc.handle, v, b, length(prompt)+1, prompt, IOBuffer(), worker, 0, w_idx,
            false, history, main_window, Main, NormalMode()
        )
        Gtk.gobject_move_ref(n, sc)
    end
end
Console(w_idx::Int, main_window, worker::TCPSocket) = Console{GtkTextView, GtkTextBuffer}(w_idx, main_window, worker)

function init_view_buffer!(v, b)
    set_gtk_property!(v, :margin_bottom, 10)
    set_gtk_property!(v, :margin_left, 4)
end

console_manager(c::Console) = console_manager(c.main_window)
worker(c::Console) = c.worker_idx == 1 ? c.worker_idx : c.worker

Base.pwd(c::Console) = remotecall_fetch(pwd, worker(c))

import Base.write
function write(c::Console, str::AbstractString)
    insert!(c.buffer, end_iter(c.buffer), str)
    place_cursor(c.buffer, end_iter(c.buffer))
end

function switch_mode(c::Console, mode::REPLMode)
    previous_prompt = prompt(c)
    c.mode = mode
    switch_prompt(c, mode, previous_prompt)
end

function check_switch_mode(c::Console, event)
    for mode in REPLModes
        #if doing(switch_key(mode), event)
        if (switch_key(mode) == event.keyval) && (mode != c.mode)
            switch_mode(c, mode)
            return true
        end
    end
    false
end

function switch_prompt(c::Console, mode::REPLMode, previous_prompt::String)

    its = GtkTextIter(c.buffer, c.prompt_position-length(previous_prompt))
    ite = GtkTextIter(c.buffer, c.prompt_position)
    replace_text(c.buffer, its, ite, prompt(c))

    diff = length(prompt(c))-length(previous_prompt)
    c.prompt_position += diff
end

prompt(c::Console) = prompt(c, c.mode)

# used to write completions before the prompt when we have more than one
# here if I use c.buffer instead it leads to crashes on v1.6
function write_before_prompt(c::Console, buffer, str::AbstractString)

    it = GtkTextIter(buffer, c.prompt_position-length(prompt(c)))
    it = Gtk.mutable(it)
    #insert!(buffer, it, str)

    ccall((:gtk_text_buffer_insert, Gtk.libgtk), Nothing,
        (Ptr{Gtk.GObject}, Ptr{GtkTextIter}, Ptr{UInt8}, Cint), buffer, it, Gtk.bytestring(str), sizeof(str))

    c.prompt_position += length(str)

    it = GtkTextIter(buffer, c.prompt_position-length(prompt(c)))
    if get_text_left_of_iter(it) != "\n"
        it = GtkTextIter(buffer, c.prompt_position-length(prompt(c)))
        insert!(buffer, it, "\n")
        c.prompt_position += 1
    end
end

function new_prompt(c::Console)
    insert!(c.buffer, end_iter(c.buffer), "\n$(prompt(c))")
    c.prompt_position = length(c.buffer)+1
    place_cursor(c.buffer, end_iter(c.buffer))
end

function clear(c::Console)
    set_gtk_property!(c.buffer, :text, "")
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

function on_return(c::Console, cmd::AbstractString)

    cmd = string(strip(cmd))#avoid getting a substring
    buffer = c.buffer

    write(c, "\n")
    if !check_worker(c) 
        write(c, "Couldn't connect to worker\n")
        return
    end

    push!(c.history, cmd)
    seek_end(c.history)

    found = false
    if c.mode == NormalMode()
        (found, t) = check_console_commands(cmd, c)
    end

    if !found
        @async on_return(c, c.mode, cmd)#we don't need the result right away
    else
        @async begin
            time = @elapsed wait(t)
            write_output_to_console(c.worker_idx, t.result, time)
        end
    end
    c.busy = true
    push!(c.main_window.statusBar, "console", "Busy")
    
    #g_timeout_add(() -> write_output_to_console(c, found), 50)
    nothing
end

function kill_current_task(c::Console)
    try #otherwise this makes the callback fail in some versions
        #@async Base.throwto(c.run_task, InterruptException())
        interrupt_task(c)
    catch
    end
end

interrupt_task(c::Console) = remotecall_fetch(RemoteGtkREPL.interrupt_task, worker(c))

function RemoteGtkREPL.process_message(m::RemoteGtkREPL.EvalDone)
    # to avoid writing at random times in the console we call the function
    # from Gtk's main loop
    g_idle_add(() -> write_output_to_console(m.console_idx, m.data, m.time))
end

RemoteGtkREPL.process_message(m::RemoteGtkREPL.StdOutData) = print_to_console_remote(m.data, m.console_idx)

@guarded (PROPAGATE) function write_output_to_console(console_idx::Int, result, time)

    c = get_console(main_window.console_manager, console_idx)

    if typeof(result) <: Tuple #console commands can return just a string
        str, v = result
    else
        str, v = (result, nothing)
    end

    !isnothing(v) && display(v)
        
    finalOutput = isnothing(str) ? "" : str

    if str == InterruptException()
        finalOutput = string(str) * "\n"
    end

    write(c, finalOutput)
    new_prompt(c)
    on_command_done(c.main_window, c)
    c.busy = false
    
    t = @sprintf("%4.6f", time)
    push!(c.main_window.statusBar, "console", "Run time $(t)s")

    return PROPAGATE#this will remove the function from the list of event sources
end

"Get the text after the prompt"
function command(c::Console)
    its = GtkTextIter(c.buffer, c.prompt_position)
    ite = GtkTextIter(c.buffer, length(c.buffer)+1)
    cmd = (its:ite).text[String]
    return cmd
end
function command(c::Console, str::AbstractString, offset::Integer)

    its = GtkTextIter(c.buffer, c.prompt_position)
    ite = GtkTextIter(c.buffer, length(c.buffer)+1)
    replace_text(c.buffer, its, ite, str)
    if offset >= 0 && c.prompt_position+offset <= length(c.buffer)
        place_cursor(c.buffer, c.prompt_position+offset)
    end
end
command(c::Console, str::AbstractString) = command(c, str, -1)

function move_cursor_to_end(c::Console)
    place_cursor(c.buffer, end_iter(c.buffer))
end
function move_cursor_to_prompt(c::Console)
    place_cursor(c.buffer, c.prompt_position)
end

"return cursor position in the prompt text"
function cursor_position(c::Console)
    a = c.prompt_position
    b = cursor_position(c.buffer)
    b-a+1
end
cursor_position(b::GtkTextBuffer) = get_gtk_property(b, :cursor_position, Int)

function select_on_ctrl_shift(direction, c::Console)

    buffer = c.buffer
    (found, its, ite) = selection_bounds(buffer)

    if direction == :start
        ite, its = its, ite
    end

    its = found ? nonmutable(buffer, its) : get_text_iter_at_cursor(buffer)

    direction == :start && move_cursor_to_prompt(c)
    direction == :end && move_cursor_to_sentence_end(buffer)

    ite = get_text_iter_at_cursor(buffer)
    select_range(buffer, ite, its)#invert here so the cursor end up on the far right
end

##
ismodkey(event::Gtk.GdkEvent, mod::Integer) =
    any(x -> x == event.keyval, [
        GdkKeySyms.Control_L, GdkKeySyms.Control_R,
        GdkKeySyms.Meta_L, GdkKeySyms.Meta_R,
        GdkKeySyms.Hyper_L, GdkKeySyms.Hyper_R,
        GdkKeySyms.Shift_L, GdkKeySyms.Shift_R
    ]) ||
    any(x -> x == event.state & mod, [
        GdkModifierType.CONTROL, GdkKeySyms.Meta_L, GdkKeySyms.Meta_R,
        PrimaryModifier, SHIFT, GdkModifierType.GDK_MOD1_MASK,
        SecondaryModifer, PrimaryModifier+SHIFT, PrimaryModifier+GdkModifierType.META])


before_prompt(console, pos::Integer) = pos < console.prompt_position
before_prompt(console) = before_prompt(console, get_gtk_property(console.buffer, :cursor_position, Int)+1)

before_or_at_prompt(console, pos::Integer) = pos <= console.prompt_position
before_or_at_prompt(console) = before_or_at_prompt(console, get_gtk_property(console.buffer, :cursor_position, Int)+1)
at_prompt(console, pos::Integer) = pos == console.prompt_position

function iters_at_console_prompt(console)
    its = GtkTextIter(console.buffer, console.prompt_position)
    ite = nonmutable(console.buffer, end_iter(console.buffer) )
    (its, ite)
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
        if !ismodkey(event, mod)
            move_cursor_to_end(console)
        end
    end

    if pos == 0#the cursor is at the prompt
        check_switch_mode(console, event) && return INTERRUPT
    end

    (found, it_start, it_end) = selection_bounds(buffer)
    
    #prevent deleting text before prompt
    if event.keyval == GdkKeySyms.BackSpace ||
       event.keyval == GdkKeySyms.Delete ||
       event.keyval == GdkKeySyms.Clear ||
       doing(Actions["cut"], event)

        if found
            
            before_prompt(console, char_offset(it_start)) && return INTERRUPT
        else
            before_or_at_prompt(console) && return INTERRUPT
        end
    end
    if doing(Actions["move_to_line_start"], event) ||
        doing(Action(GdkKeySyms.Left, PrimaryModifier), event)
        move_cursor_to_prompt(console)
        return INTERRUPT
    end
    if doing(Actions["move_to_line_end"], event) ||
       doing(Action(GdkKeySyms.Right, PrimaryModifier), event)
        move_cursor_to_end(console)
        return INTERRUPT
    end
    if doing(Actions["clear_console"], event)
        clear(console)
        new_prompt(console)
        return INTERRUPT
    end
    if doing(Action(GdkKeySyms.Right, PrimaryModifier+GdkModifierType.SHIFT), event)
        select_on_ctrl_shift(:end, console)
        return INTERRUPT
    end
    if doing(Action(GdkKeySyms.Left, PrimaryModifier+GdkModifierType.SHIFT), event)
        select_on_ctrl_shift(:start, console)
        return INTERRUPT
    end

    if doing(Action(GdkKeySyms.Left, NoModifier), event)
        if found
            at_prompt(console, char_offset(it_start)) && return INTERRUPT
        else
            before_or_at_prompt(console) && return INTERRUPT
        end
        return PROPAGATE
    end
    if doing(Action(GdkKeySyms.Left, GdkModifierType.SHIFT), event)

        at_prompt(console, char_offset(it_start)) && return INTERRUPT

        return PROPAGATE
    end

    if event.keyval == GdkKeySyms.Up
        if found
            if !before_prompt(console, offset(it_start))
                select_range(buffer, GtkTextIter(buffer, console.prompt_position), nonmutable(buffer, it_end))
                return INTERRUPT
            end
            return PROPAGATE
        end
        !history_up(console.history, prefix, cmd) && return convert(Cint, true)
        command(console, history_get_current(console.history), length(prefix))
        return INTERRUPT
    end

    if event.keyval == GdkKeySyms.Down
        hasselection(buffer) && return PROPAGATE
        history_down(console.history, prefix, cmd)
        command(console, history_get_current(console.history), length(prefix))

        return INTERRUPT
    end
    if event.keyval == GdkKeySyms.Tab
        #convert cursor position into index
        autocomplete(console, cmd, pos)
        return INTERRUPT
    end
    if doing(Actions["select_all"], event)
        #select all
        before_prompt(console) && return PROPAGATE
        #select only prompt
        its, ite = iters_at_console_prompt(console)
        select_range(buffer, its, ite)
        return INTERRUPT
    end
    if doing(Actions["interrupt_run"], event)
        kill_current_task(console)
        return INTERRUPT
    end
    if doing(Actions["copy"], event)
        auto_select_prompt(found, console, buffer)
        signal_emit(textview, "copy-clipboard", Nothing)
        return INTERRUPT
    end
    if doing(Actions["paste"], event)
        signal_emit(textview, "paste-clipboard", Nothing)
        return INTERRUPT
    end
    if doing(Actions["cut"], event)
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
        its, ite = iters_at_console_prompt(console)
        select_range(buffer, its, ite)
    end
end

function _callback_only_for_return(widgetptr::Ptr, eventptr::Ptr, user_data)
    event = convert(Gtk.GdkEvent, eventptr)
    console = user_data
    buffer = console.buffer

    cmd = command(console)

    if event.keyval == GdkKeySyms.Return
        if !console.busy
            on_return(console, cmd)
        end
        return INTERRUPT
    end
    return PROPAGATE
end

## MOUSE CLICKS

@guarded (INTERRUPT) function _console_button_press_cb(widgetptr::Ptr, eventptr::Ptr, user_data)

    textview = convert(GtkTextView, widgetptr)
    event = convert(Gtk.GdkEvent, eventptr)
    buffer = get_gtk_property(textview, :buffer, GtkTextBuffer)
    console = user_data
    main_window = console.main_window

    if event.event_type == Gtk.GdkEventType.DOUBLE_BUTTON_PRESS
        select_word_double_click(textview, buffer, Int(event.x), Int(event.y))
        return INTERRUPT
    end

    mod = get_default_mod_mask()
    if Int(event.button) == 1 && Int(event.state & mod) == Int(PrimaryModifier)
        open_method(textview) && return INTERRUPT
    end

    if rightclick(event)
        menu = buildmenu([
            MenuItem("Close Console", remove_console_cb),
            MenuItem("Add Console", add_console_cb),
            MenuItem("Clear Console", clear_console_cb),
            MenuItem("Toggle Wrap Mode", toggle_wrap_mode_cb)
            #GtkSeparatorMenuItem,
            #MenuItem("Toggle Wrap Mode", kill_current_task_cb),
            ],
            (console_manager(main_window), console, main_window)
        )
        popup(menu, event)
        return INTERRUPT
    end

    return PROPAGATE
end

global const console_mousepos = zeros(Int, 2)
global const console_mousepos_root = zeros(Int, 2)

#FIXME replace this by the same thing at the window level ?
#or put this as a field of the type.
@guarded (PROPAGATE) function console_motion_notify_event_cb(widget::Ptr,  eventptr::Ptr, user_data)
    event = convert(Gtk.GdkEvent, eventptr)

    console_mousepos[1] = round(Int, event.x)
    console_mousepos[2] = round(Int, event.y)
    console_mousepos_root[1] = round(Int, event.x_root)
    console_mousepos_root[2] = round(Int, event.y_root)
    return PROPAGATE
end

##

## auto-scroll the textview
function console_scroll_cb(widgetptr::Ptr, rectptr::Ptr, user_data)

    c = user_data
    adj = get_gtk_property(c, :vadjustment, GtkAdjustment)
    set_gtk_property!(adj, :value,
        get_gtk_property(adj, :upper, AbstractFloat) -
        get_gtk_property(adj, :page_size, AbstractFloat)
    )
    adj = get_gtk_property(c, :hadjustment, GtkAdjustment)
    set_gtk_property!(adj, :value, 0)

    nothing
end

## Auto-complete

function complete_additional_symbols(str, S)
    comp = Array{String}(undef, 0)
    for s in S
        startswith(s, str) && push!(comp, s)
    end
    comp
end

# TODO use the same code than in the editor
function autocomplete(c::Console, cmd::AbstractString, pos::Integer)

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
        comp, dotpos = completions_in_module(cmd, c)
    end
    if ctx == :file
        (comp, dotpos) = remotecall_fetch(REPL.shell_completions, worker(c), cmd, lastindex(cmd))
        comp = REPL.completion_text.(comp)
    end

    update_completions(c, comp, dotpos, cmd, lastpart)
end

function completions_in_module(cmd, c::Console)
    prefix = string(c.eval_in, ".")
    comp, dotpos = remotecall_fetch(RemoteGtkREPL.remote_completions, worker(c), prefix * cmd)
    dotpos = dotpos .- lastindex(prefix)
    comp, dotpos
end

##

# cmd is the word, including dots we are trying to complete
function update_completions(c::Console, comp, dotpos, cmd, lastpart)

    isempty(comp) && return

    dotpos = dotpos.start
    prefix = dotpos > 1 ? cmd[1:dotpos-1] : ""

    if(length(comp)>1)

        maxLength = maximum(map(length, comp))
        w = width(c.view)
        nchar_to_width(x) = 0.9*x*fontsize #TODO pango_font_metrics_get_approximate_char_width
        n_per_line = max(1, round(Int, w/nchar_to_width(maxLength)))

        out = "\n"
        for i = 1:length(comp)
            spacing = repeat(" ", maxLength-length(comp[i]))
            out = "$out $(comp[i]) $spacing"
            if mod(i, n_per_line) == 0
                out = out * "\n"
            end
        end

        write_before_prompt(c, c.buffer, out)
        out = prefix * REPL.LineEdit.common_prefix(comp)
    else
        out = prefix * comp[1]
    end

    offset = length(out)#place the cursor after the newly inserted piece
    #update entry
    out = out * lastpart
    #out = remove_filename_from_methods_def(out)

    command(c, out, offset)
end

function init!(c::Console)
    signal_connect(console_key_press_cb, c.view, "key-press-event",
    Cint, (Ptr{Gtk.GdkEvent}, ), false, c)
    signal_connect(_callback_only_for_return, c.view, "key-press-event",
    Cint, (Ptr{Gtk.GdkEvent}, ), false, c)
    signal_connect(_console_button_press_cb, c.view, "button-press-event",
    Cint, (Ptr{Gtk.GdkEvent}, ), false, c)
    signal_connect(console_motion_notify_event_cb, c, "motion-notify-event",
    Cint, (Ptr{Gtk.GdkEvent}, ), false)
    signal_connect(console_scroll_cb, c.view, "size-allocate", Nothing,
    (Ptr{Gtk.GdkRectangle}, ), false, c)

    # Note that due to historical reasons, GtkNotebook refuses to switch to a page unless the child widget is visible.
    # Therefore, it is recommended to show child widgets before adding them to a notebook.
    show(c)
    push!(console_manager(c), c)
    Gtk.GAccessor.tab_label_text(console_manager(c), c, "C" * string(length(console_manager(c))))
    g_timeout_add(()->print_to_console(c), 100)
end

"Run from the main Gtk loop, and print to console
the content of stdout_buffer"
# TODO : still needed ?
function print_to_console(console)
    
    s = String(take!(console.stdout_buffer))
    if !isempty(s)
        s = translate_colors(s)
        write(console, s)
    end
    if is_running
        return INTERRUPT
    else
        return Cint(false)
    end
end
#cfunction(print_to_console, Cint, Ptr{Console})

#FIXME dirty hack?
function translate_colors(s::AbstractString)

    s = replace(s, "\e[1m\e[31m" => "* ")
    s = replace(s, "\e[1m\e[32m" => "* ")
    s = replace(s, "\e[1m\e[31" => "* ")
    s = replace(s, "\e[0m" => "")
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
    console_manager, tab, main_window = user_data
    #add_console(main_window)
    add_remote_console(main_window, console_manager.top_module)
    nothing
end
@guarded (nothing) function remove_console_cb(btn::Ptr, user_data)
    ntbook, tab, main_window = user_data
    idx = index(ntbook, tab)
    if idx != 1#can't close the main console
        c = ntbook[idx]
#        remotecall_fetch(info, worker(c), "Goodbye.")
        splice!(ntbook, idx)
        index(ntbook, max(idx-1, 0))
    end
    nothing
end

get_current_console(console_mng::GtkNotebook) = console_mng[index(console_mng)]

function get_console(cm::ConsoleManager, idx)
    for i = 1:length(cm)
        c = get_tab(cm, i)
        c.worker_idx == idx && return c
    end
end

#this is called by remote workers
function print_to_console_remote(s, idx::Integer)
    #copy the output to the right console buffer
    c = get_console(main_window.console_manager, idx)
    if !isnothing(c)
        write(c.stdout_buffer, s)
    else
        @warn "Failed to print $s for Console $(idx)."
    end
end

## REDIRECT_STDOUT for main console

function send_stream(rd::IO, stdout_buffer::IO)
    nb = bytesavailable(rd)
    if nb > 0
        d = read(rd, nb)
        s = String(copy(d))

        if !isempty(s)
            write(stdout_buffer, s)
        end
    end
end

function watch_stream(rd::IO, c::Console)
    while !eof(rd) && is_running # blocks until something is available
        send_stream(rd, c.stdout_buffer)
        sleep(0.01) # a little delay to accumulate output
    end
end


#
