import std/[atomics, tables, typeinfo, macros, strformat, hashes, sequtils, json]
export atomics, tables, typeinfo, macros, strformat, hashes, sequtils

# static types
type
    StaticString*[N: static int] = object
        chars*     : array[N + 1, char]
        len*       : int = 0
    
    StaticSeq*[N: static int, T] = object
        data*      : array[N, T]
        len*       : int = 0
        writeLock* : Atomic[int]
    
    StaticTable*[N: static int, K, V] = object
        keysData*               : StaticSeq[N, K]
        valuesData*             : StaticSeq[N, V]
        len*                    : int = 0
        writeLock*              : Atomic[int]

    StaticJSON*[N: static int] = object
        data*       : StaticString[N]
        kind*       : JsonNodeKind

# utils
when defined(windows):
  proc mmPause() {.importc: "_mm_pause", header: "immintrin.h".}
else:
  proc mmPause() {.importc: "_mm_pause", header: "xmmintrin.h".}

template debugStaticType*(body : untyped) =
    when defined(debugStaticType):
        body

template acquire(t : untyped) : untyped =
    var expected = 0
    let desired = 1
    while not t.compareExchange(expected, desired):
        expected = 0
        mmPause()

template release(t : untyped) : untyped =
    t.store(0)

# check if type is static
proc isStaticType*(T: typedesc): bool {.compileTime.}

proc isStaticType*[T](obj : T): bool =
    return isStaticType(T)

proc isStaticArrayType[T, N](obj : array[N, T]): bool {.compileTime.} =
    return T.isStaticType

proc isStaticAtomicType[T](obj : Atomic[T]): bool {.compileTime.} =
    return T.isStaticType

proc isStaticType*(T: typedesc): bool {.compileTime.} =
    when T is SomeNumber or T is bool or T is char:
        return true
    elif T is array:
        var obj : T
        return isStaticArrayType(obj)
    elif T is tuple:
        var obj : T
        for field, val in fieldPairs(obj):
            if not val.typeOf.isStaticType:
                return false
        return true
    elif T is Atomic:
        var obj : T
        return isStaticAtomicType(obj)
    elif T is seq:
        return false
    elif T is string:
        return false
    elif T is Table:
        return false
    elif T is object:
        var obj : T
        for field, val in fieldPairs(obj):
            if not val.typeOf.isStaticType:
                return false
        return true
    elif T is ref object:
        return false
    else:
        return false

macro isStaticRefType*(T : untyped) : untyped =
    let typ = T.getType
    let exceptionMessage = "Static ref type should be a typeDesc, such as typeDesc[ref[Foo]]"
    if typ.kind == nnkBracketExpr:
        if typ[0].kind != nnkSym or typ[0].repr != "typeDesc":
            raise newException(ValueError, exceptionMessage)
        if typ[1].kind != nnkBracketExpr:
            raise newException(ValueError, exceptionMessage)
        if typ[1][0].repr != "ref":
            raise newException(ValueError, exceptionMessage)
        let baseType = typ[1][1].repr.newIdentNode
        result = quote do:
            `baseType`.isStaticType
    else:
        raise newException(ValueError, exceptionMessage)
    
    debugStaticType:
        echo "isStaticRefType macro expansion:\n", T.repr, "\n   ------------>\n", result.repr

### string
proc toStatic*[N: static int](s : string) : StaticString[N] =
    result.chars[N] = '\0'
    debugStaticType:
        if s.len > N:
            echo "[Static Type] input string is longer than ", N, " characters : ", s
    if s.len > 0:
        copyMem(addr result.chars[0], addr s[0], min(s.len, N) * sizeof(char))
    result.len = min(s.len, N)

proc capacity*[N: static int](s : var StaticString[N]) : int {.inline.} = N

proc `$`*[N: static int](s : StaticString[N]) : string =
    return $(cast[cstring](addr s.chars[0]))

proc `==`*[N: static int](s1 : StaticString[N], s2 : StaticString[N]) : bool =
    if s1.len != s2.len:
        return false
    for i in 0 ..< s1.len:
        if s1.chars[i] != s2.chars[i]:
            return false
    return true

proc `==`*[N: static int](s1 : StaticString[N], s2 : string) : bool =
    return $s1 == s2

proc `==`*[N: static int](s1 : string, s2 : StaticString[N]) : bool =
    return s1 == $s2

proc `%`*[N: static int](s : StaticString[N]) : JsonNode =
    return %($s)

### seq
proc initStaticSeq*[N: static int, T](s : var StaticSeq[N, T]) =
    s.length.store(0)

proc toStatic*[N: static int, T](s : openArray[T]) : StaticSeq[N, T] =
    debugStaticType:
        if s.len > N:
            echo "[Static Type] input seq is longer than ", N, " elements : ", s
    if s.len > 0:
        copyMem(addr result.data[0], addr s[0], min(s.len, N) * sizeof(T))
    result.length.store(min(s.len, N))

proc capacity*[N: static int, T](s : var StaticSeq) : int {.inline.} = N

proc `[]`*[N: static int, T](s : StaticSeq[N, T], i : int) : ptr T {.inline.} =
    if i < 0 or i >= s.len:
        raise newException(ValueError, fmt"Index {i} is out of range")
    return s.data[i].addr

proc `[]=`*[N: static int, T](s : var StaticSeq[N, T], i : int, val : T) =
    s.writeLock.acquire()
    defer: s.writeLock.release()
    if i < 0 or i >= s.len:
        raise newException(ValueError, fmt"Index {i} is out of range")
    s.data[i] = val

proc add*[N: static int, T](s : var StaticSeq[N, T], val : T) =
    s.writeLock.acquire()
    defer : s.writeLock.release()
    if s.len >= N:
        raise newException(ValueError, fmt"StaticSeq is full")
    s.data[s.len] = val
    s.len += 1

proc `%`*[N: static int, T](s : StaticSeq[N, T]) : JsonNode =
    result = newJArray()
    for i in 0 ..< s.len:
        result.add(%*s.data[i])

iterator items*[N: static int, T](s : StaticSeq[N, T]) : var T =
    for i in 0 ..< s.len:
        yield s.data[i]

### table
proc capacity*[N: static int, K, V](t : StaticTable[N, K, V]) : int {.inline.} = N

proc contains*[N: static int, K, V](t : StaticTable[N, K, V], key : K, lookupTable : var Table[K, int]) : bool =
    if lookupTable.hasKey(key):
        return true
    
    for i in 0 ..< t.len:
        if t.keysData[i] == key:
            lookupTable[key] = i
            return true
    
    return false

proc hasKey*[N: static int, K, V](t : StaticTable[N, K, V], key : K, lookupTable : var Table[K, int]) : bool =
    return contains(t, key, lookupTable)

proc getIndex*[N: static int, K, V](t : StaticTable[N, K, V], key : K, lookupTable : var Table[K, int]) : int =
    if lookupTable.hasKey(key):
        return lookupTable[key]
    for i in 0 ..< t.len:
        if t.keysData[i] == key:
            lookupTable[key] = i
            return i
    raise newException(KeyError, fmt"Key {key} not found in table")

proc get*[N: static int, K, V](t : StaticTable[N, K, V], key : K, lookupTable : var Table[K, int]) : ptr V =
    if lookupTable.hasKey(key):
        return t.valuesData[lookupTable[key]].addr
    for i in 0 ..< t.len:
        if t.keysData[i] == key:
            lookupTable[key] = i
            return t.valuesData[i].addr
    raise newException(KeyError, fmt"Key {key} not found in table")

proc getOrDefault*[N: static int, K, V](t : StaticTable[N, K, V], key : K, default : V, lookupTable : var Table[K, int]) : V =
    if lookupTable.contains(key):
        return t.valuesData[lookupTable[key]]
    for i in 0 ..< t.len:
        if t.keysData[i] == key:
            lookupTable[key] = i
            return t.valuesData[i]
    return default

proc add*[N: static int, K, V](t : var StaticTable[N, K, V], key : K, val : V, skipLookupTable : bool) =
    t.writeLock.acquire()
    defer : t.writeLock.release()
    for i in 0 ..< t.len:
        if t.keysData[i] == key:
            t.valuesData[i] = val
            return
    t.keysData.add(key)
    t.valuesData.add(val)
    t.len += 1

proc add*[N: static int, K, V](t : var StaticTable[N, K, V], key : K, val : V, lookupTable : var Table[K, int]) =
    t.writeLock.acquire()
    defer : t.writeLock.release()
    if lookupTable.hasKey(key):
        t.valuesData[lookupTable[key]] = val
        return
    for i in 0 ..< t.len:
        if t.keysData[i] == key:
            lookupTable[key] = i
            t.valuesData[i] = val
            return
    t.keysData.add(key)
    t.valuesData.add(val)
    t.len += 1
    lookupTable[key] = t.len - 1

proc `$`*[N: static int, K, V](t : StaticTable[N, K, V]) : string =
    result = "{"
    for i in 0 ..< t.len:
        if i > 0:
            result.add(", ")
        result.add($t.keysData[i])
        result.add(": ")
        result.add($t.valuesData[i])
    result.add("}")

proc `%`*[N: static int, K, V](t : StaticTable[N, K, V]) : JsonNode =
    result = newJObject()
    for i in 0 ..< t.len:
        result[$t.keysData[i]] = %*(t.valuesData[i])

iterator pairs*[N: static int, K, V](t : StaticTable[N, K, V]) : (K, ptr V) =
    for i in 0 ..< t.len:
        yield (t.keysData[i], t.valuesData[i].addr)

iterator keys*[N: static int, K, V](t : StaticTable[N, K, V]) : K =
    for i in 0 ..< t.len:
        yield t.keysData[i]

iterator values*[N: static int, K, V](t : StaticTable[N, K, V]) : ptr V =
    for i in 0 ..< t.len:
        yield t.valuessData[i].addr

## json
proc toStatic*[N : static int](j : JsonNode) : StaticJSON[N] =
    result.kind = j.kind

    let serialized = $j
    if serialized.len > N:
        raise newException(ValueError, fmt"Json string is too long. Maximum length is {N}. Actual length is {serialized.len}.")
    else:
        result.data = serialized.toStatic[:N]

proc `%`*[N: static int](s : StaticJSON[N]) : JsonNode =
    if s.data.len == 0:
        return newJNull()
    elif s.kind == JString:
        return %($s.data)
    else:
        return s.data.`$`.parseJson

proc `$`*[N: static int](s : StaticJSON[N]) : string =
    return $s.data

proc `[]`*[N: static int](s : StaticJSON[N], idx : int) : JsonNode =
    assert s.kind == JArray, "StaticJSON is not an array, but is a " & $s.kind
    let jsonValue = %s
    if idx < 0 or idx >= jsonValue.len:
        raise newException(ValueError, fmt"Index {idx} is out of range 0..{jsonValue.len - 1}")
    return jsonValue[idx]

proc `[]`*[N: static int](s : StaticJSON[N], key : string) : JsonNode =
    assert s.kind == JObject, "StaticJSON is not an object, but is a " & $s.kind
    let jsonValue = %s
    if not jsonValue.hasKey(key):
        raise newException(ValueError, fmt"Key {key} does not exist in StaticJSON")
    return jsonValue[key]

proc `[]=`*[N: static int](s : var StaticJSON[N], key : string, val : JsonNode) =
    assert s.kind == JObject, "StaticJSON is not an object, but is a " & $s.kind
    var jsonValue = %s
    jsonValue[key] = val
    s.data = jsonValue.toStatic[:N].data

iterator pairs*[N: static int](s : StaticJSON[N]) : (string, JsonNode) =
    assert s.kind == JObject, "StaticJSON is not an object, but is a " & $s.kind
    let jsonValue = %s
    for key, val in jsonValue.pairs:
        yield (key, val)

iterator keys*[N: static int](s : StaticJSON[N]) : string =
    assert s.kind == JObject, "StaticJSON is not an object, but is a " & $s.kind
    let jsonValue = %s
    for key in jsonValue.keys:
        yield key

iterator values*[N: static int](s : StaticJSON[N]) : JsonNode =
    assert s.kind == JObject, "StaticJSON is not an object, but is a " & $s.kind
    let jsonValue = %s
    for val in jsonValue.values:
        yield val

iterator items*[N: static int](s : StaticJSON[N]) : JsonNode =
    assert s.kind == JArray, "StaticJSON is not an array, but is a " & $s.kind
    let jsonValue = %s
    for val in jsonValue.items:
        yield val

###
when isMainModule:
    # var
    #     x : StaticTable[200, StaticString[32], StaticString[64]]
    #     lookupTable : Table[StaticString[32], int] = initTable[StaticString[32], int]()
    # x.add("foo".toStatic[:32], "bar".toStatic[:64], lookupTable)
    # x.add("foo".toStatic[:32], "baz".toStatic[:64], lookupTable)
    # x.add("foo".toStatic[:32], "baz".toStatic[:64], lookupTable)
    # for i in 0 ..< 100:
    #     x.add(i.`$`.toStatic[:32], i.`$`.toStatic[:64], lookupTable)

    # echo $x
    # echo x.contains("foo".toStatic[:32], lookupTable)
    # echo %x

    # echo x.typeof.staticSizeOf
    var data = """
        {
            "name": "John Doe",
            "age": 30,
            "address": {
                "street": "123 Main St",
                "city": "Anytown",
                "state": "CA"
            }
        }
    """.parseJson.toStatic[:128]
    echo data.typeof
    echo data["name"]
    data["name"] = %"John Smith"
    echo data
    for key, val in data.pairs:
        echo key, ": ", val