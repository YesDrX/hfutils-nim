# not supported yet: options, object variants, unicode, special float (null, NaN, Infinity, -Infinity)

import std/[macros, json, sets, strutils, tables, typetraits, unicode, parseutils, enumutils, math]
import ./static_types

export macros, json, enumutils, tables, strutils, static_types

const
    WHITE_SPACES = {' ', '\n', '\t', '\r'}

type
    SomeTable*[K, V] = Table[K, V] | OrderedTable[K, V] | TableRef[K, V] | OrderedTableRef[K, V]

##########################
proc hasKind(node: NimNode, kind: NimNodeKind): bool =
    for c in node.children:
        if c.kind == kind:
            return true
    return false

macro isObjectVariant*(v: typed): bool =
    ## Is this an object variant?
    var typ = v.getTypeImpl()
    if typ.kind == nnkSym:
        return ident("false")
    while typ.kind != nnkObjectTy:
        typ = typ[0].getTypeImpl()
    if typ[2].hasKind(nnkRecCase):
        ident("true")
    else:
        ident("false")

##########################
proc consumeWhitespace*(s: string, i: var int) =
    while i < s.len and s[i] in WHITE_SPACES:
        inc i
    
proc consumeChar*(s: string, i: var int, c: char) =
    consumeWhitespace(s, i)
    if i >= s.len:
        raise newException(ValueError, "Expected " & c & " but end reached.")

    if s[i] == c:
        inc i
    else:
        raise newException(ValueError, "Expected " & c & " but got " & s[i] & " instead.")

proc consumeSymbol*(s: string, i: var int): string =
    consumeWhitespace(s, i)
    let j = i
    while i < s.len:
        case s[i]
        of ',', '}', ']', WHITE_SPACES:
            break
        else:
            inc i
    return s[j ..< i]

########################################################################################################
# parse json string as any type (without parsing to jsonnode first)

# foward declaration
proc jsonAs*[T](s: string, i : var int, t : typedesc[T]): T

template parseNull[T](s : string, i : var int, t : typedesc[T]): untyped =
    if i + 3 < s.len and
            s[i+0] == 'n' and
            s[i+1] == 'u' and
            s[i+2] == 'l' and
            s[i+3] == 'l':
        i += 4
        when t is string:
            return ""
        elif t is ref:
            return nil
        else:
            return default(T)

proc parseAsBool(s : string, i : var int) : bool =
    if i + 3 < s.len and
            s[i+0] == 't' and
            s[i+1] == 'r' and
            s[i+2] == 'u' and
            s[i+3] == 'e':
        i += 4
        return true
    elif i + 4 < s.len and
            s[i+0] == 'f' and
            s[i+1] == 'a' and
            s[i+2] == 'l' and
            s[i+3] == 's' and
            s[i+4] == 'e':
        i += 5
        return false
    else:
        raise newException(ValueError, "Boolean true or false expected.")

proc parseAsNumber[T : SomeInteger | SomeFloat](s : string, i : var int, t : typedesc[T]) : T =
    if i == s.len or (i + 3 < s.len and
            s[i+0] == 'n' and
            s[i+1] == 'u' and
            s[i+2] == 'l' and
            s[i+3] == 'l'):
        i += 4
        when T is SomeInteger:
            return 0.T
        else:
            return NaN.T
    
    if s[i] == '"':
        let parsedStr = jsonAs(s, i, string)
        if parsedStr == "" or parsedStr.toLowerAscii() == "nan":
            i += 1
            when T is SomeInteger:
                return 0.T
            else:
                return NaN.T
        else:
            let parsedFloat = parsedStr.parseFloat
            when T is SomeInteger:
                if parsedFloat != parsedFloat.round():
                    raise newException(ValueError, "Integer expected, but got float: " & $parsedFloat)
            return parsedFloat.T
    
    var parsedFloat: float
    let chars = parseFloat(s, parsedFloat, i)
    if chars == 0:
        raise newException(ValueError, "Number expected.")
    i += chars
    when T is SomeInteger:
        if parsedFloat != parsedFloat.round():
            raise newException(ValueError, "Integer expected, but got float: " & $parsedFloat)
    return parsedFloat.T

proc consumeUnicodeEscape(s : string, i : var int, hex_len : int) =
    raise newException(ValueError, "Unicode escape is not implemented yet.")
    # #FIXME: not working right now
    # inc i # skip x/u/U
    # if i + hex_len >= s.len:
    #     raise newException(ValueError, "Expected unicode escape but end reached.")
    # echo "[consumeUnicodeEscape] ", hex_len
    # i += hex_len

proc consumeUnicodeRune(s : string, i : var int) =
    let n = runeLenAt(s, i)
    if n == 0 or i + n >= s.len:
        raise newException(ValueError, "Expected unicode rune but end reached : " & s & " at " & $i)
    i += n

proc parseAsStr(s : string, i : var int, forSkipValue : bool = false) : string =
    parseNull(s, i, string)

    let j = i
    if i == s.len:
        return ""
    
    if s[i] != '"':
        raise newException(ValueError, "String expected.")
    inc i
    while i < s.len:
        if (cast[uint8](s[i]) and 0b10000000) == 0:
            case s[i]
            of '"':
                break
            of '\\':
                if i + 1 >= s.len:
                    raise newException(ValueError, "Expected escaped character but end reached.")
                inc i # skip \
                case s[i]
                of 'x':
                    consumeUnicodeEscape(s, i, 2)
                of 'u':
                    consumeUnicodeEscape(s, i, 4)
                of 'U':
                    consumeUnicodeEscape(s, i, 8)
                else:
                    inc i
            else:
                inc i
        else:
            consumeUnicodeRune(s, i)

    if i < s.len and s[i] != '"':
        raise newException(ValueError, "Expected end of string but got " & s[i] & " instead.")
    elif i == s.len:
        raise newException(ValueError, "Expected end of string but end reached.")
    inc i
    if not forSkipValue:
        return s[j ..< i].unescape

proc parseAsStaticString[N: static[int]](s : string, i : var int, t : typedesc[StaticString[N]]) : StaticString[N] =
    let parsed = parseAsStr(s, i)
    return parsed.toStatic[:N]

proc parseAsEnum[T](s : string, i : var int, t : typedesc[T]) : T =
    var parsed : string
    if i < s.len and s[i] == '"':
        parsed = parseAsStr(s, i)
    else:
        parsed = consumeSymbol(s, i)
    try:
        return parseEnum[T](parsed)
    except:
        try:
            let parsedInt = parseInt(parsed)
            for v in T:
                if int(v) == parsedInt:
                    return v
        except:
            raise newException(ValueError, "Invalid enum value: " & parsed)

proc parseAsSeq[T](s : string, i : var int, t : typedesc[seq[T]]) : seq[T] =
    parseNull(s, i, seq[T])
    consumeChar(s, i, '[')
    while i < s.len:
        consumeWhitespace(s, i)
        if i < s.len and s[i] == ']': break
        result.add(jsonAs(s, i, T))
        consumeWhitespace(s, i)
        if i < s.len and s[i] == ',':
            inc i
        else:
            break
    consumeWhitespace(s, i)
    consumeChar(s, i, ']')

proc parseAsStaticSeq[N: static[int], T](s : string, i : var int, t : typedesc[StaticSeq[N, T]]) : StaticSeq[N, T] =
    when not T.isStaticType:
        {.error: "Static type expected.".}
    let parsed = parseAsSeq(s, i, seq[T])
    if parsed.len > N:
        raise newException(ValueError, "Too many elements for StaticSeq.")
    if parsed.len > 0:
        copyMem(result.data[0].addr, parsed[0].addr, parsed.len * sizeof(T))
    result.len = parsed.len

proc parseAsArray[N : static[int], T](s : string, i : var int, t : typedesc[array[N, T]]) : array[N, T] =
    parseNull(s, i, array[N, T])
    let parsed = parseAsSeq(s, i, seq[T])
    if parsed.len != N:
        raise newException(ValueError, "Array expected.")
    for i in 0 ..< N:
        result[i] = parsed[i]

proc parseAsTable[K, V](s : string, i : var int, t : typedesc[SomeTable[K, V]]) : SomeTable[K, V] =
    parseNull(s, i, t)
    consumeChar(s, i, '{')
    while i < s.len:
        consumeWhitespace(s, i)
        if i < s.len and s[i] == '}': break
        let key = jsonAs[K](s, i, K)
        consumeChar(s, i, ':')
        consumeWhitespace(s, i)
        result[key] = jsonAs[V](s, i, V)
        consumeWhitespace(s, i)
        if i < s.len and s[i] == ',':
            inc i
        else:
            break
    consumeChar(s, i, '}')

proc parseAsStaticTable[N, K, V](s : string, i : var int, t : typedesc[StaticTable[N, K, V]]) : StaticTable[N, K, V] =
    when not V.isStaticType or not K.isStaticType:
        {.error: "Static type expected for table.".}
    let parsed = parseAsTable[K, V](s, i, Table[K, V])
    if parsed.len > N:
        raise newException(ValueError, "Too many elements for StaticTable.")
    for k, v in parsed.pairs:
        result.add(k, v, skipLookupTable = true)

proc skipValue(s: string, i: var int) =
    ## Used to skip values of extra fields.
    consumeWhitespace(s, i)
    if i < s.len and s[i] == '{':
        consumeChar(s, i, '{')
        while i < s.len:
            consumeWhitespace(s, i)
            if i < s.len and s[i] == '}':
                break
            skipValue(s, i)
            consumeChar(s, i, ':')
            skipValue(s, i)
            consumeWhitespace(s, i)
            if i < s.len and s[i] == ',':
                inc i
        consumeChar(s, i, '}')
    elif i < s.len and s[i] == '[':
        consumeChar(s, i, '[')
        while i < s.len:
            consumeWhitespace(s, i)
            if i < s.len and s[i] == ']':
                break
            skipValue(s, i)
            consumeWhitespace(s, i)
            if i < s.len and s[i] == ',':
                inc i
        consumeChar(s, i, ']')
    elif i < s.len and s[i] == '"':
        discard parseAsStr(s, i, forSkipValue = true)
    else:
        discard consumeSymbol(s, i)

proc parseAsObject[T](s : string, i : var int, t : typedesc[T]) : T =
    parseNull(s, i, T)
    consumeChar(s, i, '{')
    while i < s.len:
        consumeWhitespace(s, i)
        if i < s.len and s[i] == '}': break
        let key = parseAsStr(s, i)
        consumeWhitespace(s, i)
        consumeChar(s, i, ':')
        consumeWhitespace(s, i)
        var keyIsValid = false
        for k, v in result.fieldPairs:
            if k == key:
                v = jsonAs[type(v)](s, i, type(v))
                keyIsValid = true
        if not keyIsValid:
            when not defined(release):
                echo "[JSON] Unknown key: `" & key & "` for type `" & $t & "`"
            skipValue(s, i)
        consumeWhitespace(s, i)
        if i < s.len and s[i] == ',':
            inc i
        else:
            break
    consumeWhitespace(s, i)
    consumeChar(s, i, '}')

proc parseAsRefObject[T](s : string, i : var int, t : typedesc[ref T]) : ref T =
    if i + 3 < s.len and
        s[i+0] == 'n' and
        s[i+1] == 'u' and
        s[i+2] == 'l' and
        s[i+3] == 'l':
        i += 4
        return nil
    result = new(T)
    result[] = parseAsObject(s, i, T)

proc parseAsJson(s : string, i : var int) : JsonNode =
    if i == s.len:
        return newJNull()

    if i < s.len and s[i] == '{':
        result = newJObject()
        consumeChar(s, i, '{')
        while i < s.len:
            consumeWhitespace(s, i)
            if i < s.len and s[i] == '}':
                break
            let k = parseAsStr(s, i)
            consumeChar(s, i, ':')
            consumeWhitespace(s, i)
            let e = parseAsJson(s, i)
            result[k] = e
            consumeWhitespace(s, i)
            if i < s.len and s[i] == ',':
                inc i
        consumeChar(s, i, '}')
    elif i < s.len and s[i] == '[':
        result = newJArray()
        consumeChar(s, i, '[')
        while i < s.len:
            consumeWhitespace(s, i)
            if i < s.len and s[i] == ']':
                break
            let e = parseAsJson(s, i)
            result.add(e)
            consumeWhitespace(s, i)
            if i < s.len and s[i] == ',':
                inc i
        consumeChar(s, i, ']')
    elif i < s.len and s[i] == '"':
        result = newJString(parseAsStr(s, i))
    else:
        let data = consumeSymbol(s, i)
        if data == "null":
            result = newJNull()
        elif data == "true":
            result = newJBool(true)
        elif data == "false":
            result = newJBool(false)
        elif data.len > 0 and data[0] in {'0'..'9', '-', '+'}:
            try:
                result = newJInt(parseInt(data))
            except ValueError:
                try:
                    result = newJFloat(parseFloat(data))
                except ValueError:
                    raise newException(ValueError, "Invalid number: " & data)
        else:
            raise newException(ValueError, "Unexpected JSON data: " & data)

proc parseAsStaticJson[N : static[int]](s : string, i : var int, t : typedesc[StaticJSON[N]]) : StaticJSON[N] =
    parseAsJson(s, i).toStatic[:N]

proc parseAsDistinct[T : distinct](s : string, i : var int, t : typedesc[T]) : T =
    jsonAs(s, i, T.distinctBase).T

template addCustomHook[T](s: string, i: var int, t: typedesc[T]) =
    mixin customParseHook
    customParseHook(s, i, t)

proc jsonAs*[T](s: string, i : var int, t : typedesc[T]): T =
    when compiles(addCustomHook(s, i, T)):
        addCustomHook(s, i, T)
    # mixin customParseHook
    # customParseHook(s, i, t)
    
    let j = i
    consumeWhitespace(s, i)
    try:
        when T is bool:
            return parseAsBool(s, i)
        elif T is SomeInteger or T is SomeFloat:
            return parseAsNumber(s, i, T)
        elif T is string: ## Asicii only for now
            return parseAsStr(s, i)
        elif T is StaticString:
            return parseAsStaticString(s, i, T)
        elif T is char:
            let parsed = parseAsStr(s, i)
            if parsed.len != 1:
                raise newException(ValueError, "Character expected.")
            return parsed[0]
        elif T is seq:
            return parseAsSeq(s, i, T)
        elif T is StaticSeq:
            return parseAsStaticSeq(s, i, T)
        elif T is array:
            return parseAsArray(s, i, T)
        elif T is set:
            {.error: "Unsupported type: " & $T.}
        elif T is enum:
            return parseAsEnum(s, i, T)
        elif T is Table:
            return parseAsTable(s, i, T)
        elif T is StaticTable:
            return parseAsStaticTable(s, i, T)
        elif T is JsonNode:
            return parseAsJson(s, i)
        elif T is StaticJSON:
            return parseAsStaticJson(s, i, T)
        elif T is ref object:
            return parseAsRefObject(s, i, T)
        elif T is object:
            return parseAsObject(s, i, T)
        elif T is distinct:
            return parseAsDistinct(s, i, T)
        else:
            {.error: "Unsupported type: " & $T.}
    except ValueError:
        echo "[JSON] Error: when parsing for type `" & $T & "`, got error: `" & getCurrentExceptionMsg() & "`"
        echo "[JSON] Data:\n" & s[j ..< s.len] & "\n"
        raise

proc jsonAs*[T](s: string, t : typedesc[T]): T =
    var i = 0
    return jsonAs(s, i, t)

########################################################################################################
# parse jsonnode to any type

proc nodeAs*[T](n : JsonNode, t : typedesc[T]) : T

proc nodeAsBool(n : JsonNode) : bool =
    if n.kind == JBool:
        return n.getBool
    elif n.kind == JString:
        return n.getStr.toLowerAscii == "true"
    else:
        raise newException(ValueError, "Invalid boolean value: " & $n & " (kind = " & $n.kind & ")")

proc nodeAsInt[T: SomeInteger](n : JsonNode) : T =
    if n.kind == JInt:
        return n.getInt.T
    elif n.kind == JFloat:
        let parsed = n.getFloat
        if parsed.round() == parsed:
            return parsed.int.T
        else:
            raise newException(ValueError, "Invalid integer value: " & $n & " (kind = " & $n.kind & ")")
    elif n.kind == JNull:
        return 0.T
    elif n.kind == JString:
        return n.getStr.parseInt.T
    else:
        raise newException(ValueError, "Invalid integer value: " & $n & " (kind = " & $n.kind & ")")

proc nodeAsFloat[T : SomeFloat](n : JsonNode) : T =
    if n.kind == JFloat:
        return n.getFloat.T
    elif n.kind == JInt:
        return n.getInt.T
    elif n.kind == JString:
        if n.getStr.len == 0 or n.getStr.toLowerAscii == "nan":
            return NaN.T
        return n.getStr.parseFloat.T
    elif n.kind == JNull:
        return NaN.T
    else:
        raise newException(ValueError, "Invalid float value: " & $n & "(kind = " & $n.kind & ")")

proc nodeAsStr(n : JsonNode) : string =
    if n.kind == JString:
        return n.getStr
    else:
        return $n

proc nodeAsStaticString[N : static int](n : JsonNode, t : typedesc[StaticString[N]]) : StaticString[N] =
    return nodeAsStr(n).toStatic[:N]

proc nodeAsSeq[T](n : JsonNode, t : typedesc[seq[T]]) : seq[T] =
    if n.kind == JNull:
        return @[]

    if n.kind == JArray:
        for i in n.items:
            result.add(nodeAs(i, T))
    else:
        raise newException(ValueError, "Invalid array value: " & $n & "(kind = " & $n.kind & ")")

proc nodeAsArray[N: static int, T](n : JsonNode, t : typedesc[array[N, T]]) : array[N, T] =
    let parsed = nodeAsSeq(n, seq[T])
    if parsed.len != N:
        raise newException(ValueError, "Invalid array value: " & $n & "(kind = " & $n.kind & ")")
    for i in 0 ..< N:
        result[i] = parsed[i]

proc nodeAsStaticSeq[N, T](n : JsonNode, t : typedesc[StaticSeq[N, T]]) : StaticSeq[N, T] =
    let parsed = nodeAsSeq(n, seq[T])
    return parsed.toStatic[:N, T]

proc nodeAsEnum[T : enum](n : JsonNode) : T =
    if n.kind == JString:
        return parseEnum[T](n.getStr)
    elif n.kind == JInt:
        for v in T:
            if v.int == n.getInt:
                return v
        raise newException(ValueError, "Invalid enum value: " & $n & "(kind = " & $n.kind & ")")
    else:
        raise newException(ValueError, "Invalid enum value: " & $n & "(kind = " & $n.kind & ")")

proc nodeAsTable[K, V](n : JsonNode, t : typedesc[SomeTable[K, V]]) : SomeTable[K, V] =
    if n.kind == JNull:
        return
    
    elif n.kind == JArray and n.len == 0:
        return
  
    if n.kind == JObject:
        for k, v in n.pairs:
            result[ nodeAs(%k, K) ] = nodeAs(v, V)
    
    else:
        raise newException(ValueError, "Invalid table value: " & $n & "(kind = " & $n.kind & ")")

proc nodeAsStaticTable[N, K, V](n : JsonNode, t : typedesc[StaticTable[N, K, V]]) : StaticTable[N, K, V] =
    let parsed = nodeAsTable(n, Table[K, V])
    for k, v in parsed.pairs:
        result.add(k, v, skipLookupTable = true)

proc nodeAsJson(n : JsonNode) : JsonNode =
    return n

proc nodeAsStaticJson[N](n : JsonNode, t : typedesc[StaticJson[N]]) : StaticJson[N] =
    return n.toStatic[:N]

proc nodeAsObject[T](n : JsonNode, t: typedesc[T]) : T =
    if n.kind == JNull:
        return default(T)

    result = default(T)
    if n.kind == JObject:
        for k, v in result.fieldPairs:
            if k in n:
                v = nodeAs(n[k], type(v))
    
    else:
        raise newException(ValueError, "Invalid object value: " & $n & " (kind = " & $n.kind & ")")

proc nodeAsRefObject[T](n : JsonNode, t: typedesc[T]) : T =
    if n.kind == JNull:
        return nil
    
    new(result)
    if n.kind == JObject:
        for k, v in result[].fieldPairs:
            if k in n:
                v = nodeAs(n[k], type(v))
    else:
        raise newException(ValueError, "Invalid object value: " & $n & "(kind = " & $n.kind & ")")

template addCustomNodeAsHook[T](n : JsonNode, t : typedesc[T]): untyped =
    mixin customNodeAsHook
    customNodeAsHook(n, t)

proc nodeAs*[T](n : JsonNode, t : typedesc[T]) : T =
    when compiles(addCustomNodeAsHook(n, t)):
        addCustomNodeAsHook(n, t)
    
    try:
        when T is bool:
            return nodeAsBool(n)
        elif T is SomeSignedInt or T is SomeUnsignedInt:
            return nodeAsInt[T](n)
        elif T is SomeFloat:
            return nodeAsFloat[T](n)
        elif T is string:
            return nodeAsStr(n)
        elif T is char:
            let parsed = nodeAsStr(n)
            if parsed.len != 1:
                raise newException(ValueError, "Invalid char value: " & $n & " (kind = " & $n.kind & ")")
            return parsed[0]
        elif T is StaticString:
            return nodeAsStaticString(n, T)
        elif T is seq:
            return nodeAsSeq(n, T)
        elif T is StaticSeq:
            return nodeAsStaticSeq(n, T)
        elif T is array:
            return nodeAsArray(n, T)
        elif T is enum:
            return nodeAsEnum[T](n)
        elif T is SomeTable:
            return nodeAsTable(n, T)
        elif T is StaticTable:
            return nodeAsStaticTable(n, T)
        elif T is JsonNode:
            return nodeAsJson(n)
        elif T is StaticJSON:
            return nodeAsStaticJson(n, T)
        elif T is distinct:
            return nodeAs(n, T.distinctBase).T
        elif T is ref object:
            return nodeAsRefObject(n, T)
        elif T is object:
            return nodeAsObject(n, T)
        else:
            {.error: "Unsupported type: " & $T.}
    except ValueError:
        echo "[JSON] Error: when parsing for type `" & $T & "`, got error: `" & getCurrentExceptionMsg() & "`"
        echo "[JSON] Json Data Serialized:\n" & $n & "\n"
        raise

########################################################################################################
# dump any type to json
proc jsonDump*[T](t : T) : string

proc jsonDumpStr(s : string) : string =
    return s.escape

proc jsonDumpStaticString(s : StaticString) : string =
    return s.`$`.escape

proc jsonDumpChar(c : char) : string =
    return "\"" & c & "\""

proc jsonDumpTable[K, V](t : SomeTable[K, V]) : string =
    result = "{"
    for k, v in t:
        result.add(jsonDump(k))
        result.add(":")
        result.add(jsonDump(v))
        result.add(", ")
    if result.len > 2:
        result = result[0 ..< result.len - 2]
    result.add("}")

proc jsonDumpStaticTable[N, K, V](t : StaticTable[N, K, V]) : string =
    result = "{"
    for k, v in t:
        result.add(jsonDump(k))
        result.add(":")
        result.add(jsonDump(v[]))
        result.add(", ")
    if result.len > 2:
        result = result[0 ..< result.len - 2]
    result.add("}")

proc jsonDumpObject[T](t : T) : string =
    result = "{"
    for k, v in fieldPairs(t):
        result.add(jsonDumpStr(k))
        result.add(":")
        result.add(jsonDump(v))
        result.add(", ")
    if result.len > 2:
        result = result[0 ..< result.len - 2]
    result.add("}")

proc jsonDumpArray[T](s : openArray[T]) : string =
    result = "["
    for i in 0 ..< s.len:
        result.add(jsonDump(s[i]))
        if i < s.len - 1:
            result.add(", ")
    result.add("]")

proc jsonDumpStaticSeq[N, T](s : StaticSeq[N, T]) : string =
    result = "["
    for i in 0 ..< s.len:
        result.add(jsonDump(s.data[i]))
        if i < s.len - 1:
            result.add(", ")
    result.add("]")

proc jsonDumpDistinct[T](t : T) : string =
    return jsonDump(distinctBase(T)(t))

template addCustomJsonDumpHook[T](t: T) =
    mixin customJsonDumpHook
    customJsonDumpHook(t)

proc jsonDump*[T](t : T) : string =
    when compiles(addCustomJsonDumpHook(t)):
        addCustomJsonDumpHook(t)
    
    when T is bool or T is SomeSignedInt or T is SomeUnsignedInt:
        return $t
    elif T is SomeFloat:
        if t.isNan:
            return "null"
        else:
            return $t
    elif T is char:
        return jsonDumpChar(t)
    elif T is string:
        return jsonDumpStr(t)
    elif T is StaticString:
        return jsonDumpStaticString(t)
    elif T is seq or T is array or T is set:
        return jsonDumpArray(t)
    elif T is StaticSeq:
        return jsonDumpStaticSeq(t)
    elif T is SomeTable:
        return jsonDumpTable(t)
    elif T is StaticTable:
        return jsonDumpStaticTable(t)
    elif T is enum:
        return t.`$`.escape
    elif T is JsonNode or T is StaticJSON:
        return $t
    elif T is ref object:
        if t == nil:
            return "null"
        else:
            return jsonDumpObject(t[])
    elif T is object:
        return jsonDumpObject(t)
    elif T is distinct:
        return jsonDumpDistinct(t)
    else:
        {.error: "Unsupported type: " & $T.}

##########################
# yaml dump
proc yamlDump*[T](t : T, indent : int = 0) : string

type ComplexYamlField = seq | array | set | StaticSeq | object | ref object | SomeTable | StaticTable

template addCustomIsComplexYamlFieldHook[T](t: typedesc[T]): untyped =
    mixin customIsComplexYamlFieldHook
    customIsComplexYamlFieldHook(t)

proc isComplexYamlField[T](t : typedesc[T]) : bool =
    when compiles(addCustomIsComplexYamlFieldHook(t)):
        addCustomIsComplexYamlFieldHook(t)
    when T is ComplexYamlField:
        return true
    else:
        return false

proc yamlDumpArray[T](s : openArray[T], indent : int) : string =
    let indention = "    ".repeat(indent)
    when T.isComplexYamlField:
        for idx, item in s.pairs:
            result = result & indention & "-\n" & yamlDump(item, indent + 1)
            if idx < s.len - 1: result = result & "\n"
    else:
        for idx, item in s.pairs:
            result = result & indention & "- " & yamlDump(item, 0)
            if idx < s.len - 1: result = result & "\n"

template yamlDumpKV(s : untyped, pairsIterator: untyped, indent : int) : untyped =
    var anyKV : bool = false
    for k, v in s.pairsIterator:
        result = result & indention & yamlDump(k, indent) & ":"
        when type(v).isComplexYamlField:
            result = result & "\n" & yamlDump(v, indent + 1) & "\n"
        else:
            result = result & " " & yamlDump(v, 0) & "\n"
        anyKV = true
    if anyKV: # remove last \n
        result = result[0 ..< result.len - 1]

template addCustomYamlDumpHook[T](t: T) =
    mixin customYamlDumpHook
    customYamlDumpHook(t)

proc yamlDump*[T](t : T, indent : int = 0) : string =
    when compiles(addCustomYamlDumpHook(t)):
        addCustomYamlDumpHook(t)
    
    let indention {.used.} = "    ".repeat(indent)

    when T is bool or T is SomeSignedInt or T is SomeUnsignedInt or T is SomeFloat:
        return indention & $t

    elif T is char or T is string or T is StaticString:
        result = t.`$`.escape
        return result[1 ..< result.len - 1]

    elif T is seq or T is array or T is set or T is StaticSeq:
        return yamlDumpArray(t, indent)

    elif T is distinct:
        return indention & yamlDump(distinctBase(T)(t), indent)

    elif T is enum:
        return indention & t.`$`

    elif T is StaticJSON:
        return indention & $t

    elif T is JsonNode:
        if t != nil:
            return indention & $t
        else:
            return indention & "null"

    elif T is object or T is ref object:
        yamlDumpKV(t, fieldPairs, indent)

    elif T is ptr:
        yamlDumpKV(t[], fieldPairs, indent)
    
    elif T is SomeTable or T is StaticTable:
        yamlDumpKV(t, pairs, indent)

    else:
        {.error: "Unsupported type: " & $T.}

when isMainModule:
    type
        Hobby = enum
            SWIM = "Swimming"
            READ = "Reading"
        
        City = object
            name : string
            population : int
            state : string

        Address = object
            street : string
            city : City
            
        User = object
            name : string
            age : int
            id : int = 1
            address: Address
            meta: JsonNode
            hobby: seq[Hobby]
            hobby2: seq[Hobby]
            
        
    let data = """
    {
        "name": "John Doe",
        "age": 30,
        "id": 1,
        "address": {
            "street": "123 Main St",
            "city": {
                "name": "New York",
                "population": 1000000,
                "state": "NY"
            }
        },
        "meta" : {
            "key1": "value1",
            "key2": "value2",
            "key3": [1, 2, 3],
            "key4": {"nested": "object"}
        },
        "hobby": ["Reading"],
        "hobby2": ["Reading", "Swimming"]
    }
    """
    let user = jsonAs(data, User)
    echo user
    echo user.yamlDump

