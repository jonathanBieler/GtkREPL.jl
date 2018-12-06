using ApplicationBuilder, GtkREPL, Compat
cd("/Applications/")

builddir = "/Applications/GtkREPL.app/Contents/Libraries/"
r = s->joinpath("/Users/jbieler/.julia/",s)

#Gtk libs
gtk_libs = [
    :libgdk,
    :libgdk_pixbuf,
    :libgio,
    :libglib,
    :libgobject,
    :libgtk,
]

copy_libs(src,dest) = try cp(src, joinpath(builddir,dest); force=true, follow_symlinks=false) catch err 
    @warn (src, joinpath(builddir,dest))
    throw(err)
end

hb_root = "/Users/jbieler/.julia/packages/Homebrew/l8kUw/deps/usr/"

function copy_dir(src,libs)
    mkpath(joinpath(builddir,src))
    @info "copying to $(joinpath(builddir,src))"
    for lib in libs
        copy_libs(joinpath(hb_root,src,lib),joinpath(src,lib))
    end
end

# copy whole directories
copy_dir("Cellar",[
    "gtk+3","glib","gdk-pixbuf","cairo","pango","fribidi","atk","libepoxy","gettext",
    "libffi","pcre","pixman","fontconfig","freetype","libpng","harfbuzz","icu4c",
    "graphite2","librsvg","libcroco","jpeg","libtiff",
])
copy_dir("lib",["glib-2.0","gdk-pixbuf-2.0"])
copy_dir("opt",[
    "gtk+3","glib","gdk-pixbuf","cairo","pango","fribidi","atk","libepoxy","gettext",
    "libffi","pcre","pixman","fontconfig","freetype","libpng","harfbuzz","icu4c",
    "graphite2","librsvg","libcroco","jpeg","libtiff"
])

#copy individual files in "lib"
for lib in [Core.eval(GtkREPL.Gtk,l) for l in gtk_libs]
    copy_libs(lib, joinpath("lib", basename(lib)) )
end

#copy individual files in "bin"
mkpath(joinpath(builddir,"bin"))
for lib in [joinpath(hb_root,"bin/gdk-pixbuf-query-loaders")]
    copy_libs(lib, joinpath("bin", basename(lib)) )
end

function fix_library(l; relpath="@executable_path/../Libraries")

    name = basename(l)

    @assert isfile(l)
    chmod(l, 0o777)

    run(`install_name_tool -id "$name" $l`)

    try
        
        external_deps = readlines(pipeline(`otool -L $l`,`sed 's/(.*)$//'`))
       
        #`sed 's/(.*)$//'`

        for line in external_deps
            line = strip(line)
            path = line
            line = line[end] == ':' ? line[1:end-1] : line
            #@info line
            if !occursin(hb_root,line)
                @info "skipped $line"
                continue
            end

            depname = strip(split(line,hb_root)[2])
            if !isfile(joinpath(builddir,depname))
                @show line
                error("file not found: $(joinpath(builddir,depname))")
            end

            cmd = `install_name_tool -change "$path" "$(relpath)/$(depname)" $l`
            #println(cmd)
            run(cmd)
        end
    catch err
        error(err)
    end
end

#list all libraries and fix them
libs = readlines(pipeline(`find $builddir -type f -name "*.dylib" -o -name "*.so"`))
for lib in libs
    #fix_library(lib, relpath = "@executable_path/../Libraries")
    fix_library(lib, relpath = builddir)
end
#copy gdk-pixbuf-query-loaders in the same folder than our application to simplify pathing
mkpath(joinpath(builddir,"..","MacOS"))
cp(joinpath(builddir,"bin","gdk-pixbuf-query-loaders"), joinpath(builddir,"..","MacOS","gdk-pixbuf-query-loaders"); force=true, follow_symlinks=true)
#fix_library(joinpath(builddir,"..","MacOS","gdk-pixbuf-query-loaders"), relpath = "@executable_path/../Libraries")
fix_library(joinpath(builddir,"..","MacOS","gdk-pixbuf-query-loaders"), relpath = builddir)

build_app_bundle(r("dev/GtkREPL/build_app.jl"), appname="GtkREPL", builddir="/Applications/",
    resources=[r("dev/GtkREPL/config/default_settings.jl")],
    #libraries=libs,
    verbose=true,
)