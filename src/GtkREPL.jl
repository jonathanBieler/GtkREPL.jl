module GtkREPL
    using Gtk
    using RemoteGtkREPL
    include("JuliaWordsUtils.jl")
    using .JuliaWordsUtils
    include("GtkTextUtils.jl")
    using .GtkTextUtils
    using Sockets, Distributed, Printf, REPL, Pkg
    
    import Gtk: GtkTextIter, char_offset, get_default_mod_mask, GdkKeySyms
    import Gtk.GAccessor.end_iter
    import REPL.REPLCompletions.completions
    import Sockets: TCPServer

    export repl, RemoteGtkREPL, Pkg
    export MenuItem, buildmenu

    global const HOMEDIR = @__DIR__
    global const PROPAGATE = convert(Cint, false)
    global const INTERRUPT = convert(Cint, true)

    global const fontsize = 13
    
    global main_window = nothing #need to be defined at init
    function set_main_window(w)
        global main_window = w
    end 

    include("Actions.jl")
    include("REPLWindow.jl")
    include("CommandHistory.jl")
    include("ConsoleManager.jl")
    include("AddConsoleTab.jl")
    include("REPLMode.jl")
    include("Console.jl")
    include("ConsoleCommands.jl")
    include("MenuUtils.jl")
    include("utils.jl")
    
    if !isfile(joinpath(HOMEDIR, "../config", "user_settings.jl"))
        cp(joinpath(HOMEDIR, "../config", "default_settings.jl"), joinpath(HOMEDIR, "../config", "user_settings.jl"))
    end
    include(joinpath("../config", "user_settings.jl"))

    function reload()
        Core.eval(GtkREPL, quote
        include(joinpath(HOMEDIR, "Actions.jl"))
        include(joinpath(HOMEDIR, "REPLWindow.jl"))
        include(joinpath(HOMEDIR, "CommandHistory.jl"))
        include(joinpath(HOMEDIR, "ConsoleManager.jl"))
        include(joinpath(HOMEDIR, "AddConsoleTab.jl"))
        include(joinpath(HOMEDIR, "REPLMode.jl"))
        include(joinpath(HOMEDIR, "Console.jl"))
        include(joinpath(HOMEDIR, "ConsoleCommands.jl"))
        include(joinpath(HOMEDIR, "MenuUtils.jl"))
        include(joinpath(HOMEDIR, "utils.jl"))
        include(joinpath(HOMEDIR, "../config", "user_settings.jl"))
        end)
    end

    function send_stream(rd::IO)
        nb = bytesavailable(rd)
        if nb > 0
            d = read(rd, nb)
            s = String(copy(d))
            if !isempty(s)
                try 
                    print_to_console_remote(s, 1)
                catch err
                    @warn err
                end
            end
        end
    end
    
    function watch_stream(rd::IO)
        while !eof(rd) # blocks until something is available
            send_stream(rd)
            sleep(0.01) # a little delay to accumulate output
        end
    end

    function gtkrepl(T=GtkTextView, B=GtkTextBuffer)
        global main_window = REPLWindow()
        console_mng = ConsoleManager(main_window)
        init!(main_window, console_mng)
        init!(console_mng)

        #c = Console{T, B}(1, main_window, TCPSocket())
        #init!(c)
        RemoteGtkREPL.estalbish_connection(console_mng.port, 1, "GtkREPL")

        showall(main_window)

        @async begin
            isinteractive() && sleep(0.1)
            if !@isdefined watch_stdio_task
                global read_stdout, wr = redirect_stdout()
                global watch_stdio_task = @async watch_stream(read_stdout)
            end
        end

    end
    
    function __init__() 
        global is_running = true
    end

end # module
