__precompile__()
module GtkREPL
    using Gtk
    using RemoteGtkREPL
    using GtkExtensions
    using JuliaWordsUtils
    using GtkTextUtils

    import Gtk.GtkTextIter
    import Base.REPLCompletions.completions

    export repl

    global const HOMEDIR = @__DIR__
    global const PROPAGATE = convert(Cint,false)
    global const INTERRUPT = convert(Cint,true)

    global const fontsize = 13

    include("Actions.jl")
    include("REPLWindow.jl")
    include("CommandHistory.jl")
    include("ConsoleManager.jl")
    include("REPLMode.jl")
    include("Console.jl")
    include("ConsoleCommands.jl")

    function reload()
        eval(GtkREPL, quote
        include(joinpath(HOMEDIR,"Actions.jl"))
        include(joinpath(HOMEDIR,"REPLWindow.jl"))
        include(joinpath(HOMEDIR,"CommandHistory.jl"))
        include(joinpath(HOMEDIR,"ConsoleManager.jl"))
        include(joinpath(HOMEDIR,"REPLMode.jl"))
        include(joinpath(HOMEDIR,"Console.jl"))
        include(joinpath(HOMEDIR,"ConsoleCommands.jl"))
        end)
    end

    function gadfly()
        @eval begin
            import Gadfly
            export Gadfly
        end
        RemoteGtkREPL.gadfly()
    end

    function gtkrepl(T=GtkTextView,B=GtkTextBuffer)
        global main_window = REPLWindow()
        console_mng = ConsoleManager(main_window)
        c = Console{T,B}(1, main_window, TCPSocket())
        #push!(console_mng,c)

        main_window.console_manager = console_mng
        push!(main_window,console_mng)

        init!(c)

        showall(main_window)
    end
    #__init__() = gtkrepl()

end # module
