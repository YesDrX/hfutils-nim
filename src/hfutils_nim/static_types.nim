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

# utils
when defined(windows):
  proc mmPause() {.importc: "_mm_pause", header: "immintrin.h".}
elif defined(poisx):
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

proc `[]`*[N: static int, T](s : StaticSeq[N, T], i : int) : T {.inline.} =
    if i >= s.len:
        raise newException(ValueError, fmt"Index {i} is out of range")
    return s.data[i]

proc `[]=`*[N: static int, T](s : var StaticSeq[N, T], i : int, val : T) {.inline.} =
    s.writeLock.acquire()
    defer: s.writeLock.release()
    if i >= s.len:
        raise newException(ValueError, fmt"Index {i} is out of range")
    s.data[i] = val

proc add*[N: static int, T](s : var StaticSeq[N, T], val : T) =
    s.writeLock.acquire()
    defer : s.writeLock.release()
    if s.len >= N:
        raise newException(ValueError, fmt"StaticSeq is full")
    s.data[s.len] = val
    s.len += 1

proc getPointer*[N: static int, T](s : StaticSeq[N, T], i : int) : ptr T {.inline.} =
    if i >= s.len:
        raise newException(ValueError, fmt"Index {i} is out of range")
    return addr s.data[i]

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

proc get*[N: static int, K, V](t : StaticTable[N, K, V], key : K, lookupTable : var Table[K, int]) : var V =
    if lookupTable.hasKey(key):
        return t.valuesData[lookupTable[key]]
    for i in 0 ..< t.len:
        if t.keysData[i] == key:
            lookupTable[key] = i
            return t.valuesData[i]
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

proc getPointer*[N: static int, K, V](t : StaticTable[N, K, V], key : K, lookupTable : var Table[K, int]) : ptr V =
    let index = getIndex(t, key, lookupTable)
    return addr t.valuesData[index]

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

iterator pairs*[N: static int, K, V](t : StaticTable[N, K, V]) : (K, var V) =
    for i in 0 ..< t.len:
        yield (t.keysData[i], t.valuesData[i])

iterator keys*[N: static int, K, V](t : StaticTable[N, K, V]) : K =
    for i in 0 ..< t.len:
        yield t.keysData[i]

iterator values*[N: static int, K, V](t : StaticTable[N, K, V]) : var V =
    for i in 0 ..< t.len:
        yield t.valuessData[i]

###
proc staticSizeOfStaticTable*[N: static int, K, V](t : typedesc[StaticTable[N, K, V]]) : int {.compileTime.} =
    return sizeof(t) - sizeof(Table[K, int])

proc staticSizeOf*(t : typedesc) : int {.compileTime.} =
    when t is StaticTable:
        return staticSizeOfStaticTable(t)
    else:
        return sizeof(t)

###
when isMainModule:
    var
        x : StaticTable[200, StaticString[32], StaticString[64]]
        lookupTable : Table[StaticString[32], int] = initTable[StaticString[32], int]()
    x.add("foo".toStatic[:32], "bar".toStatic[:64], lookupTable)
    x.add("foo".toStatic[:32], "baz".toStatic[:64], lookupTable)
    x.add("foo".toStatic[:32], "baz".toStatic[:64], lookupTable)
    for i in 0 ..< 100:
        x.add(i.`$`.toStatic[:32], i.`$`.toStatic[:64], lookupTable)

    echo $x
    echo x.contains("foo".toStatic[:32], lookupTable)
    echo %x

    echo x.typeof.staticSizeOf
