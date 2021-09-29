mutable struct ConsoleManager <: GtkNotebook

    handle::Ptr{Gtk.GObject}
    main_window
    server::TCPServer
    port::UInt16
    top_module::Module
    watch_stdout_task::Task
    stdout
    stderr

    function ConsoleManager(main_window, top_module=GtkREPL)

        ntb = GtkNotebook()
        set_gtk_property!(ntb, :vexpand, true)
        port, server = RemoteGtkREPL.start_server()

        n = new(ntb.handle, main_window, server, port, top_module)
        Gtk.gobject_move_ref(n, ntb)
    end
end

function init!(console_mng::ConsoleManager)
    add_plus_button(console_mng)
    # add a task in Gtk's main main that writes stdout buffer in the console
    signal_connect(console_mng_button_press_cb,console_mng, "button-press-event",
    Cint, (Ptr{Gtk.GdkEvent},),false,console_mng.main_window)
    signal_connect(console_mng_switch_page_cb, console_mng, "switch-page", Nothing, (Ptr{Gtk.GtkWidget},Int32), false)
end

function init_stdout!(console_mng::ConsoleManager,watch_stdout_task,stdout,stderr)
    console_mng.watch_stdout_task = watch_stdout_task
    console_mng.stdout = stdout
    console_mng.stderr = stderr
end

function add_remote_console(main_window, mod=GtkREPL)
    port = console_manager(main_window).port
    id = length(console_manager(main_window)) + 1
    p = joinpath(HOMEDIR,"remote_console_startup.jl")
    #julia_path = Config.julia_path
    julia_path = ENV["_"] # ^_^
    s = "tell application \"Terminal\" to do script \"$(julia_path) -i --color=no \\\"$p\\\" $port $id $mod\""
    run(`osascript -e $s`)
end

function add_remote_console_cb(id, port)
    @info "GtkREPL: Starting console for port $port with id $id"

    c = try
        worker = connect(port)

        c = Console(id, main_window, worker)
        c.worker_port = port
        init!(c)

        #for some reason I need to warm-up things here, otherwise it bugs later on.
        @assert remotecall_fetch(identity, GtkREPL.worker(c),1) == 1

        showall(c.main_window)
        c
    catch err
        @warn err
    end

    RemoteGtkREPL.remotecall_fetch(println, worker(c),"Worker connected")
    "done"
end

@guarded (INTERRUPT) function console_mng_button_press_cb(widgetptr::Ptr, eventptr::Ptr, user_data)

    ntbook = convert(GtkNotebook, widgetptr)
    event = convert(Gtk.GdkEvent, eventptr)
    main_window = user_data #TODO ntbook should be a console manager with a MainWindow field?

    if rightclick(event)
        menu = buildmenu([
            MenuItem("Close Console", remove_console_cb),
            MenuItem("Add Console", add_console_cb)
            ],
            (ntbook, get_current_console(ntbook), main_window)
        )
        popup(menu,event)
        return INTERRUPT
    end

    return PROPAGATE
end

function console_mng_switch_page_cb(widgetptr::Ptr, pageptr::Ptr, pagenum::Int32, user_data)

    cm = convert(GtkNotebook, widgetptr)
    c  = convert(Gtk.GtkWidget, pageptr)

    on_console_mng_switch_page(cm, c)

    nothing
end

function current_console(m::ConsoleManager) 
    c = m[index(m)]
    c isa Console && return c
    for c in m
        c isa Console && return c
    end
    c
end

function stop_console_redirect(main_window)

    t = main_window.console_manager.watch_stdout_task
    out = main_window.console_manager.stdout
    #err = main_window.console_manager.stderr

# The task end itself when is_running == false
#    try
#        Base.throwto(t, InterruptException())
#    end

    sleep(0.1)
    redirect_stdout(out)
    #redirect_stderr(err)
end
