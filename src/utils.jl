function select_word(it::GtkTextIter,buffer::GtkTextBuffer,include_dot::Bool)#include_dot means we include "." in word boundary def

    (txt, line_start, line_end) = get_line_text(buffer,it)

    pos = offset(it) - offset(line_start) +1#not sure about the +1 but it feels better
    if pos <= 0
        return ("",GtkTextIter(buffer,offset(it)),
        GtkTextIter(buffer,offset(it)))
    end

    word,i,j = extend_word(pos, txt, include_dot)

    its = GtkTextIter(buffer, i + offset(line_start) )
    ite = GtkTextIter(buffer, j + offset(line_start) + 1)

    return (word,its,ite)
end
select_word(it::GtkTextIter,buffer::GtkTextBuffer) = select_word(it,buffer,true)

function select_word_backward(it::GtkTextIter,buffer::GtkTextBuffer,include_dot::Bool)

    (txt, line_start, line_end) = get_line_text(buffer,it)
    pos = offset(it) - offset(line_start) #position of cursor in txt

    if pos <= 0 || length(txt) == 0
        return ("",GtkTextIter(buffer,offset(it)),
        GtkTextIter(buffer,offset(it)))
    end

    txt = CharArray(txt,pos)
    (i,j) = select_word_backward(pos,txt,include_dot)

    its = GtkTextIter(buffer, i + offset(line_start) )
    ite = GtkTextIter(buffer, offset(it))

    return (txt[i:j],its,it)
end
