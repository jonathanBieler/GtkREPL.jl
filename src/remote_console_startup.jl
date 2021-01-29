using RemoteGtkREPL
RemoteGtkREPL.estalbish_connection(ARGS)

#= RemoteGtkREPL.remotecall_fetch(include_string, GtkREPLWorker.gtkrepl, Main,
    "$(GtkREPLWorker.remote_mod).add_remote_console_cb($(GtkREPLWorker.id), $(GtkREPLWorker.port))"
) =#

# put important things in a module for safety
#= module GtkREPLWorker

    using RemoteGtkREPL, Sockets

    gtkrepl_port = parse(Int,ARGS[1])
    global const id = parse(Int, ARGS[2]) # console/worker id
    global const remote_mod = ARGS[3]    # the module calling us as a String

    port, server = RemoteGtkREPL.start_server()

    global const gtkrepl = connect(gtkrepl_port)

    RemoteGtkREPL.init(gtkrepl, id)
end =#



#ploting stuff
#= function gadfly()
    @eval begin
        RemoteGtkREPL.gadfly()

        export figure
        import Base: show, display

        show(io::IO, p::Gadfly.Plot) = write(io,"Gadfly.Plot(...)")
        function display(p::Gadfly.Plot)
            remotecall_fetch(display, GtkREPLWorker.gtkrepl, p)
            nothing
        end

        figure() = remotecall_fetch(RemoteGtkREPL.eval_command_remotely, GtkREPLWorker.gtkrepl,"figure()", Main)
        figure(i::Integer) = remotecall_fetch(RemoteGtkREPL.eval_command_remotely, GtkREPLWorker.gtkrepl,"figure($i)", Main)
    end
end =#

#start Gadfly by default
#using Gadfly
#gadfly()






