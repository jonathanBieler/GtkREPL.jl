module JuliaWordsUtils

    import Base: length, getindex, lastindex, firstindex

    export select_word_backward, get_word_backward, extend_word

    """
        CharArray is a Vector of Char with a few convenience methods.
    """
    struct CharArray
        c::Vector{Char}
        function CharArray(s::AbstractString,l::Integer)
            l > length(s) && error("Offset larger than string length.")
            ca = Char[]

            for (count,c) in enumerate(s)
                push!(ca,c)
                count >= l && break
            end
            new(ca)
        end
        CharArray(s::AbstractString) = CharArray(s,length(s))
    end

    length(s::CharArray) = length(s.c)
    getindex(s::CharArray,i::Integer) = s.c[i]
    getindex(s::CharArray,i::UnitRange) = string(s.c[i]...)
    lastindex(s::CharArray) = lastindex(s.c)
    firstindex(s::CharArray) = firstindex(s.c)

    # maybe not the most efficient way of doing this.
    global const word_boundaries = [
        ' ','\n','\t','(',')','[',']',',','\'',
        '*','+','-','/','\\','%','{','}','#',':',
        '&','|','?','!','"','$','=','>','<'
    ]
    global const word_boundaries_dot = [word_boundaries; '.']#includes dot in function of the context

    function is_word_boundary(s::Char,stop_at_dot::Bool)
        w = stop_at_dot ? word_boundaries_dot : word_boundaries
        for c in w
            s == c && return true
        end
        false
    end

    function extend_word_backward(it::Integer,ca::CharArray,stop_at_dot::Bool)
        it <= 1 && return 1
        while !is_word_boundary(ca[it],stop_at_dot)
            it == 1 && return it
            it = it-1
        end
        return it+1 #I stopped at the boundary
    end

    function extend_word_forward(it::Integer,ca::CharArray,stop_at_dot::Bool)
        it >= length(ca) && return length(ca)
        while !is_word_boundary(ca[it],stop_at_dot)
            it == length(ca) && return it
            it = it+1
        end
        return it-1 #I stopped at the boundary
    end

    function extend_word(pos::Integer,txt::String,stop_at_dot=true)
        ca = CharArray(txt)

        pos > length(ca) && return "",pos,pos
        pos < 1 && return "",pos,pos

        is_word_boundary(ca[pos],stop_at_dot) && return ca[pos:pos], pos, pos

        i = extend_word_backward(pos,ca,stop_at_dot)
        j = extend_word_forward(pos,ca,stop_at_dot)

        if j < length(txt) && ca[j+1] == '!' #allow for a single ! at the end of words
           j = j + 1
        end
        ca[i:j], i, j
    end

    function select_word_backward(pos::Integer,ca::CharArray,stop_at_dot::Bool)
        j = pos
        #allow for autocomplete on functions
        pos = ca[pos] == '(' ? pos-1 : pos
        pos = ca[pos] == '!' ? pos-1 : pos

        is_word_boundary(ca[pos],stop_at_dot) && return pos, pos

        i = extend_word_backward(pos,ca,stop_at_dot)

        #allow for \alpha and such
        i = (i > 1 && ca[i-1] == '\\') ? i-1 : i

        return (i,j)
    end
    select_word_backward(pos::Integer,txt::String,stop_at_dot=true) = select_word_backward(pos,CharArray(txt,pos),stop_at_dot)

    function get_word_backward(pos::Integer,txt::String,stop_at_dot=true)
        ca = CharArray(txt,pos)
        i,j = select_word_backward(pos,ca,stop_at_dot)
        ca[i:j]
    end

end # module