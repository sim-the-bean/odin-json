package json

import "core:log"
import "core:os"
import "core:strconv"
import "core:unicode/utf8"

Object :: distinct map[String]Value;
Array :: distinct [dynamic]Value;
String :: distinct string;
Number :: distinct f64;
Bool :: distinct bool;

// not using #no_nil, cause `null` is a valid json value
Value :: union{Object, Array, String, Number, Bool};

read_from_path :: proc(path: string) -> (value: Value, ok: bool) {
    bytes: []byte;
    if bytes, ok = os.read_entire_file(path); !ok {
        log.errorf("odin-json: could not read from path %v", path);
        return;
    }
    text := string(bytes);
    defer delete(text);
    return read_from_string(text);
}

read_from_string :: proc(text: string) -> (value: Value, ok: bool) {
    i := 0;
    value, ok = parse_element(text, &i);
    return;
}

@private
peek_rune_no_err :: proc(text: string, pos: int) -> rune {
    return utf8.rune_at_pos(text, pos);
}

@private
peek_rune :: proc(text: string, pos: int) -> (r: rune, ok: bool) {
    r = peek_rune_no_err(text, pos);
    ok = r != utf8.RUNE_ERROR;
    if !ok {
        log.errorf("odin-json: invalid character at %v", pos);
        return;
    }
    return;
}

@private
next_rune :: proc(text: string, pos: ^int) -> (r: rune, ok: bool) {
    r, ok = peek_rune(text, pos^);
    pos^ += 1;
    return;
}

@private
parse_whitespace :: proc(text: string, pos: ^int) {
    r := peek_rune_no_err(text, pos^);
    switch r {
    case ' ', '\n', '\v', '\t':
        next_rune(text, pos);
        parse_whitespace(text, pos);
    }
}

@private
parse_colon :: proc(text: string, pos: ^int) -> (ok: bool) {
    r: rune;
    if r, ok = next_rune(text, pos); !ok do return;
    switch r {
    case ':':
        ok = true;
    case:
        log.errorf("odin-json: unexpected character at %v, expected `:`", pos^ - 1);
        ok = false;
    }
    return;
}

@private
parse_element :: proc(text: string, pos: ^int) -> (value: Value, ok: bool) {
    parse_whitespace(text, pos);
    if value, ok = parse_value(text, pos); !ok do return;
    parse_whitespace(text, pos);
    return;
}

@private
parse_elements :: proc(text: string, pos: ^int) -> (array: Array, ok: bool) {
    array = make(Array);
    for {
        value: Value;
        if value, ok = parse_element(text, pos); !ok do return;
        append(&array, value);
        r: rune;
        if r, ok = peek_rune(text, pos^); !ok do return;
        if r == ',' {
            next_rune(text, pos);
        } else {
            return;
        }
    }
}

@private
parse_member :: proc(text: string, pos: ^int) -> (key: String, value: Value, ok: bool) {
    parse_whitespace(text, pos);
    if key, ok = parse_string(text, pos); !ok do return;
    parse_whitespace(text, pos);
    if ok = parse_colon(text, pos); !ok do return;
    if value, ok = parse_element(text, pos); !ok do return;
    return;
}

@private
parse_members :: proc(text: string, pos: ^int) -> (object: Object, ok: bool) {
    object = make(Object);
    for {
        key: String;
        value: Value;
        if key, value, ok = parse_member(text, pos); !ok do return;
        object[key] = value;
        r: rune;
        if r, ok = peek_rune(text, pos^); !ok do return;
        if r == ',' {
            next_rune(text, pos);
        } else {
            return;
        }
    }
}

@private
parse_value :: proc(text: string, pos: ^int) -> (value: Value, ok: bool) {
    r: rune;
    if r, ok = peek_rune(text, pos^); !ok do return;
    switch r {
    case '{':
        value, ok = parse_object(text, pos);
    case '[':
        value, ok = parse_array(text, pos);
    case '"':
        value, ok = parse_string(text, pos);
    case '-', '0'..'9':
        value, ok = parse_number(text, pos);
    case:
        value, ok = parse_identifier(text, pos);
    }
    return;
}

@private
parse_object :: proc(text: string, pos: ^int) -> (value: Object, ok: bool) {
    r: rune;
    if r, ok = next_rune(text, pos); !ok || r != '{' {
        log.errorf("odin-json: unexpected character at %v, expected `{{`", pos^ - 1);
        ok = false;
        return;
    }
    
    parse_whitespace(text, pos);
    
    object: Object;
    if r, ok = peek_rune(text, pos^); !ok {
        log.errorf("odin-json: unexpected character atf %v, expected `}}`", pos^ - 1);
        ok = false;
        return;
    } else if r == '}' {
        object = make(Object);
    } else {
        if object, ok = parse_members(text, pos); !ok do return;
    }
    
    if r, ok = next_rune(text, pos); !ok || r != '}' {
        delete(object);
        log.errorf("odin-json: unexpected character at %v, expected `}}`", pos^ - 1);
        ok = false;
        return;
    }
    
    ok = true;
    value = object;
    return;
}

@private
parse_array :: proc(text: string, pos: ^int) -> (value: Array, ok: bool) {
    r: rune;
    if r, ok = next_rune(text, pos); !ok || r != '[' {
        log.errorf("odin-json: unexpected character at %v, expected `[`", pos^ - 1);
        ok = false;
        return;
    }
    
    parse_whitespace(text, pos);
    
    array: Array;
    if r, ok = peek_rune(text, pos^); !ok {
        log.errorf("odin-json: unexpected character atf %v, expected `]`", pos^ - 1);
        ok = false;
        return;
    } else if r == ']' {
        array = make(Array);
    } else {
        if array, ok = parse_elements(text, pos); !ok do return;
    }
    
    if r, ok = next_rune(text, pos); !ok || r != ']' {
        delete(array);
        log.errorf("odin-json: unexpected character at %v, expected `]`", pos^ - 1);
        ok = false;
        return;
    }
    
    ok = true;
    value = array;
    return;
}

@private
parse_string :: proc(text: string, pos: ^int) -> (value: String, ok: bool) {
    r: rune;
    if r, ok = next_rune(text, pos); !ok || r != '"' {
        log.errorf("odin-json: unexpected character at %v, expected `\"`", pos^ - 1);
        ok = false;
        return;
    }
    
    str: String;
    if r, ok = peek_rune(text, pos^); !ok {
        log.errorf("odin-json: unexpected character atf %v, expected `\"`", pos^ - 1);
        ok = false;
        return;
    } else if r == ']' {
        str = String(string(make([]u8, 0)));
    } else {
        if str, ok = parse_characters(text, pos); !ok do return;
    }
    
    if r, ok = next_rune(text, pos); !ok || r != '"' {
        delete(string(str));
        log.errorf("odin-json: unexpected character at %v, expected `\"`", pos^ - 1);
        ok = false;
        return;
    }
    
    ok = true;
    value = str;
    return;
}

@private
parse_identifier :: proc(text: string, pos: ^int) -> (value: Value, ok: bool) {
    r: rune;
    if r, ok = peek_rune(text, pos^); !ok do return;
    switch r {
    case 'n':
        return parse_identifier_priv(text, pos, "null", nil);
    case 't':
        return parse_identifier_priv(text, pos, "true", Bool(true));
    case 'f':
        return parse_identifier_priv(text, pos, "false", Bool(false));
    case:
        log.errorf("odin-json: invalid identifier at %v, valid identifiers are `true`, `false` and `null`", pos^ - 1);
        ok = false;
        return;
    }
}

@private
parse_identifier_priv :: proc(text: string, pos: ^int, ident: string, val: Value) -> (value: Value, ok: bool) {
    for r0 in ident {
        r1: rune;
        if r1, ok = next_rune(text, pos); !ok do return;
        if r0 != r1 {
            log.errorf("odin-json: invalid identifier at %v, valid identifiers are `true`, `false` and `null`", pos^ - 1);
            ok = false;
            return;
        }
    }
    value = val;
    ok = true;
    return;
}

@private
parse_number :: proc(text: string, pos: ^int) -> (number: Number, ok: bool) {
    runes := make([dynamic]rune);
    defer delete(runes);
    r: rune;
    if r, ok = peek_rune(text, pos^); !ok do return;
    if r == '-' {
        append(&runes, r);
        next_rune(text, pos);
    }
    if r, ok = peek_rune(text, pos^); !ok do return;
    do_loop := true;
    switch r {
    case '0':
        append(&runes, r);
        next_rune(text, pos);
        do_loop = false;
    }
    if do_loop {
        loop1: for {
            if r, ok = peek_rune(text, pos^); !ok do return;
            switch r {
            case '0'..'9':
                append(&runes, r);
                next_rune(text, pos);
            case '.', 'e', 'E':
                break loop1;
            case:
                break loop1;
            }
        }
    }
    if r, ok = peek_rune(text, pos^); !ok do return;
    if r == '.' {
        append(&runes, r);
        next_rune(text, pos);
        loop2: for {
            if r, ok = peek_rune(text, pos^); !ok do return;
            switch r {
            case '0'..'9':
                append(&runes, r);
                next_rune(text, pos);
            case 'e', 'E':
                break loop2;
            case:
                break loop2;
            }
        }
    }
    if r, ok = peek_rune(text, pos^); !ok do return;
    if r == 'e' || r == 'E' {
        append(&runes, r);
        next_rune(text, pos);
        if r, ok = peek_rune(text, pos^); !ok do return;
        if r == '+' || r == '-' {
            append(&runes, r);
            next_rune(text, pos);
        }
        loop3: for {
            if r, ok = peek_rune(text, pos^); !ok do return;
            switch r {
            case '0'..'9':
                append(&runes, r);
                next_rune(text, pos);
            case:
                break loop3;
            }
        }
    }
    str := utf8.runes_to_string(runes[:]);
    defer delete(str);
    float: f64;
    if float, ok = strconv.parse_f64(str); !ok {
        log.errorf("odin-json: invalid number at %v", pos^ - 1);
        ok = false;
        return;
    }
    number = Number(float);
    ok = true;
    return;
}

@private
parse_characters :: proc(text: string, pos: ^int) -> (str: String, ok: bool) {
    runes := make([dynamic]rune);
    defer delete(runes);
    r: rune;
    loop: for {
        if r, ok = peek_rune(text, pos^); !ok do return;
        switch r {
        case '"':
            break loop;
        case '\\':
            next_rune(text, pos);
            if r, ok = peek_rune(text, pos^); !ok do return;
            switch r {
            case '"':
                next_rune(text, pos);
                append(&runes, '"');
            case '\\':
                next_rune(text, pos);
                append(&runes, '\\');
            case '/':
                next_rune(text, pos);
                append(&runes, '/');
            case 'b':
                next_rune(text, pos);
                append(&runes, '\b');
            case 'f':
                next_rune(text, pos);
                append(&runes, '\f');
            case 'n':
                next_rune(text, pos);
                append(&runes, '\n');
            case 'r':
                next_rune(text, pos);
                append(&runes, '\r');
            case 't':
                next_rune(text, pos);
                append(&runes, '\t');
            case 'u':
                // TODO
                ok = false;
                log.errorf("odin-json: unicode characters are not yet implemented at %v", pos^ - 1);
                return;
            }
        case '\u0020'..'\U0010ffff':
            next_rune(text, pos);
            append(&runes, r);
        case:
            ok = false;
            log.errorf("odin-json: invalid character at %v", pos^ - 1);
            return;
        }
    }
    ok = true;
    str = String(utf8.runes_to_string(runes[:]));
    return;
}
