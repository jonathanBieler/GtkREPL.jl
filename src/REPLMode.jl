# That's not great but it will do for now,
# It would be better to reuse Base.REPL code

abstract type REPLMode end

struct NormalMode <: REPLMode end
struct ShellMode <: REPLMode end
struct HelpMode <: REPLMode end
struct PkgMode <: REPLMode end

global const REPLModes = [NormalMode(), ShellMode(), HelpMode(), PkgMode()]

prompt(c,mode::REPLMode) = string(mode,">")
prompt(c,mode::NormalMode) = string(c.eval_in,">")
prompt(c,mode::ShellMode) = "shell>"
prompt(c,mode::HelpMode) = "help?>"
prompt(c,mode::PkgMode) = "pkg>"

switch_key(mode::NormalMode) = Action(Gtk.GdkKeySyms.BackSpace, NoModifier, "")
switch_key(mode::ShellMode)  = Action(0x03b, NoModifier, "")
switch_key(mode::HelpMode)   = Action(0x03f, GdkModifierType.SHIFT, "")
switch_key(mode::PkgMode)    = Action(0x05d, NoModifier, "")
#FIXME add these to Gtk.GdkKeySyms https://gitlab.gnome.org/GNOME/gtk/blob/master/gdk/gdkkeysyms.h

on_return(c,mode::REPLMode,cmd)    = nothing
on_return(c,mode::NormalMode,cmd)  = remotecall_fetch(RemoteGtkREPL.eval_command_remotely, worker(c), cmd,string(c.eval_in))
on_return(c,mode::HelpMode,cmd)    = remotecall_fetch(RemoteGtkREPL.eval_command_remotely, worker(c), "@doc $cmd",string(c.eval_in))
on_return(c,mode::ShellMode,cmd)   = remotecall_fetch(RemoteGtkREPL.eval_shell_remotely,   worker(c), cmd,string(c.eval_in))
on_return(c,mode::PkgMode,cmd)     = remotecall_fetch(RemoteGtkREPL.eval_command_remotely, worker(c), "Pkg.REPLMode.pkgstr(\"$cmd\")","Main")
