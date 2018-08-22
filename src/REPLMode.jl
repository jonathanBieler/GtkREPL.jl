# That's not great but it will do for now,
# It would be better to reuse Base.REPL code

abstract type REPLMode end

struct NormalMode <: REPLMode end
struct ShellMode <: REPLMode end
struct HelpMode <: REPLMode end

global const REPLModes = [NormalMode(), ShellMode(), HelpMode()]

prompt(c,mode::REPLMode) = string(mode,">")
prompt(c,mode::NormalMode) = string(c.eval_in,">")
prompt(c,mode::ShellMode) = "shell>"
prompt(c,mode::HelpMode) = "help?>"

switch_key(mode::NormalMode) = Action(Gtk.GdkKeySyms.BackSpace, NoModifier, "")
switch_key(mode::ShellMode) = Action(0x03b, NoModifier, "")
switch_key(mode::HelpMode) = Action(0x03f, GdkModifierType.SHIFT, "")
#FIXME add these to Gtk.GdkKeySyms https://gitlab.gnome.org/GNOME/gtk/blob/master/gdk/gdkkeysyms.h

on_return(c,mode::REPLMode,cmd::String) = nothing
on_return(c,mode::NormalMode,cmd::String) = remotecall_fetch(RemoteGtkREPL.eval_command_remotely,worker(c),cmd,c.eval_in)
on_return(c,mode::HelpMode,cmd::String) = remotecall_fetch(RemoteGtkREPL.eval_command_remotely,worker(c),"@doc $cmd",c.eval_in)
on_return(c,mode::ShellMode,cmd::String) = remotecall_fetch(RemoteGtkREPL.eval_shell_remotely,worker(c),cmd)