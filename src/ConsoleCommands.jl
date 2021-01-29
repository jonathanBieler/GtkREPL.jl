"
    ConsoleCommand

Commands that are first executed in the console before Julia code.

- `edit filename` : open filename in the Editor. If filename does not exists it will be created instead.
- `clc` : clear the console.
- `pwd` : get the current working directory.
- `cd dirname` : set the current working directory.
- `open name` : open name with default application (e.g. `open .` opens the current directory).
- `mkdir dirname` : make a new directory.
"
mutable struct ConsoleCommand
	r::Regex
	f::Function
	completion_context::Symbol
end

global const console_commands = Array{ConsoleCommand}(undef, 0)
add_console_command(r::Regex, f::Function) = push!(console_commands, ConsoleCommand(r, f, :normal))
add_console_command(r::Regex, f::Function, c::Symbol) = push!(console_commands, ConsoleCommand(r, f, c))

#first try to match line number
#add_console_command(r"^edit (.*):(\d+)", (m, c) -> begin
#    try
#        line = parse(Int, m.captures[2])
#        q = "\""
#        remotecall_fetch(include_string, worker(c), "eval(GtkIDE, :(
#            open_in_new_tab($(q)$(m.captures[1])$(q), line=$(line))
#        ))")
#    catch
#        println("Invalid line number: $(m.captures[2])")
#    end
#    nothing
#end, :file)
#add_console_command(r"^edit (.*)", (m, c) -> begin
#    q = "\""
#    remotecall_fetch(include_string, worker(c), "eval(GtkIDE, :(
#        open_in_new_tab($(q)$(m.captures[1])$(q))
#    ))")
#    nothing
#end, :file)

add_console_command(r"^clc$", (m, c) -> begin
    clear(c)
    nothing
end)
add_console_command(r"^pwd$", (m, c) -> begin
    return pwd(c) * "\n"
end)
add_console_command(r"^ls\s+(.*)", (m, c) -> begin
    try
        f(args...) = remotecall_fetch(readdir, worker(c), args...)
        files = m.captures[1] == "" ? f() : f(m.captures[1])
        s = ""
        for f in files
            s = string(s, f, "\n")
        end
        return s
	catch err
		return sprint(show, err) * "\n"
	end
end, :file)
add_console_command(r"^ls$", (m, c) -> begin
	try
        files = remotecall_fetch(readdir, worker(c))
        s = ""
        for f in files
            s = string(s, f, "\n")
        end
        return s
	catch err
		return sprint(show, err) * "\n"
	end
end, :file)

add_console_command(r"^cd (.*)", (m, c) -> begin
	try
        v = m.captures[1]
	    if !remotecall_fetch(isdir, worker(c), v)
            return "cd: $v: No such file or directory"
        end
        remotecall_fetch(cd, worker(c), v)
	    
		return pwd(c) * "\n"
	catch err
		return sprint(show, err) * "\n"
	end
end, :file)
add_console_command(r"^\?\s*(.*)", (m, c) -> begin
    try
        h = Symbol(m.captures[1])#TODO: run this on worker
        h = Base.doc(Base.Docs.Binding(
            Base.Docs.current_module(), h)
        )
        h = Markdown.plain(h)
        return h
    catch err
        return sprint(show, err) * "\n"
    end
end)
add_console_command(r"^open (.*)", (m, c) -> begin
	try
        v = m.captures[1]
        if Sys.iswindows()
            remotecall_fetch(run, worker(c), `cmd /c start "$v" `)
        end
        if Sys.isapple()
            remotecall_fetch(run, worker(c), `open $v`)
        end
        return "\n"
	catch err
		return sprint(show, err) * "\n"
    end
end, :file)
add_console_command(r"^mkdir (.*)", (m, c) -> begin
	try
        v = m.captures[1]
        remotecall_fetch(mkdir, worker(c), v)
	catch err
		return sprint(show, err) * "\n"
	end
end, :file)

add_console_command(r"^evalin (.*)", (m, c) -> begin
	try
        v = m.captures[1]
        v == "?" && return string(c.eval_in) * "\n"

        m = Core.eval(Main, Meta.parse(v))
        typeof(m) != Module && error("evalin : $v is not a module")
        c.eval_in = m
	catch err
		return sprint(show, err) * "\n"
	end
	nothing
end)

add_console_command(r"^morespace", (m, c) -> begin
	try
        main_window = c.main_window
        visible(main_window.menubar, !visible(main_window.menubar))
        visible(main_window.editor.sourcemap, !visible(main_window.editor.sourcemap))
	catch err
		return sprint(show, err) * "\n"
	end
	nothing
end)

##
function console_commands_context(cmd::AbstractString)
    for c in console_commands
        m = match(c.r, cmd)
        if m != nothing
            return (c.completion_context, m)
        end
    end
    return (:normal, nothing)
end

function interpolate_console_command(cmd, c)

    !occursin('$', cmd) && return true, cmd

    s = string('"', cmd, '"')
    s = Base.parse_input_line(s)
    out = try
        remotecall_fetch(Core.eval, worker(c), Main, s)
    catch err
        @warn err
        return false, cmd
    end
    return true, out
end

function check_console_commands(cmd::AbstractString, c::Console)
    for co in console_commands
        m = match(co.r, cmd)
        if m != nothing
            success, i_cmd = interpolate_console_command(cmd, c)# need to be run only when we have a match
            !success && continue
            m = match(co.r, i_cmd)
            m == nothing && continue
            return (true, @async begin co.f(m, c) end)
        end
    end
    return (false, nothing)
end
