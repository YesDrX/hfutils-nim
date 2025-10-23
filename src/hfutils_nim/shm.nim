import std/[memfiles, os, strformat, macros]
import ./static_types

export memfiles, static_types

when defined(windows):
    import std/winlean

type
    ObjectShm*[T] = object
        name*        : string
        data*        : ptr T
        size*        : int
        isOwner*     : bool
        when defined(posix):
            memfile* : Memfile
        elif defined(windows):
            handle*  : Handle

when defined(windows):
    const
        WIN_TRUE  = 1.int32
        WIN_FALSE = 0.int32

    proc getFullName(name : string) : string {.inline.} =
        return "Local\\" & name

    proc openFileMappingA(dwDesiredAccess : DWORD, bInheritHandle : WINBOOL, lpName : cstring) : Handle {.stdcall, dynlib: "kernel32", importc: "OpenFileMappingA".}
    proc createFileMappingA(
        hFile: Handle,
        lpFileMappingAttributes: pointer,
        flProtect: DWORD,
        dwMaximumSizeHigh: DWORD,
        dwMaximumSizeLow: DWORD,
        lpName: cstring
    ): Handle {.stdcall, dynlib: "kernel32", importc: "CreateFileMappingA".}
    proc unmapViewOfFile(lpBaseAddress: pointer): WINBOOL {.stdcall, dynlib: "kernel32", importc: "UnmapViewOfFile".}

    proc createSharedMemory*(name : string, size : int) : tuple[handle: HANDLE, mem: pointer] =
        let fullName = name.getFullName.cstring
        let handle = createFileMappingA(
            INVALID_HANDLE_VALUE,
            nil,
            PAGE_READWRITE,
            0,
            size.DWORD,
            fullName
        )
        if handle == 0:
            raise newException(OSError, fmt"Failed to create shared memory: {osLastError()}")
        
        result.mem = mapViewOfFileEx(
                    handle,
                    FILE_MAP_READ or FILE_MAP_WRITE,
                    0,
                    0,
                    size.WinSizeT,
                    nil
                )
        if result.mem == nil:
            raise newException(OSError, fmt"Failed to map shared memory: {osLastError()}")
        
        result.handle = handle
    
    proc getSharedMemory*(name : string, size : int) : tuple[handle: HANDLE, mem: pointer] =
        let fullName = name.getFullName.cstring
        let handle = openFileMappingA(
            FILE_MAP_READ or FILE_MAP_WRITE,
            WIN_FALSE,
            fullName
        )
        if handle == 0:
            raise newException(OSError, fmt"Failed to open shared memory `{name}`: {osLastError()}")
        
        result.mem = mapViewOfFileEx(
            handle,
            FILE_MAP_READ or FILE_MAP_WRITE,
            0,
            0,
            size.WinSizeT,
            nil
        )
        if result.mem == nil:
            raise newException(OSError, fmt"Failed to map shared memory: {osLastError()}")
        
        result.handle = handle

proc `=destroy`*[T](self : var ObjectShm[T]) =
    when defined(windows):
        if self.data != nil:
            discard unmapViewOfFile(self.data)
            discard closeHandle(self.handle)
            self.data = nil
    else:
        if self.data != nil:
            self.memfile.close()
            self.data = nil
        if self.isOwner:
            let filename = "/dev/shm/" & self.name
            if fileExists(filename):
                removeFile(filename)

proc createObjectShm*[T](name : string) : ObjectShm[T] =
    when not T.isStaticType:
        raise newException(ValueError, "T must be a static type for ObjectShm")
    let size = sizeof(T)

    when defined(windows):
        let (handle, mem) = createSharedMemory(name, size)
        result.data = cast[ptr T](mem)
        result.handle = handle
    else:
        let filename = "/dev/shm/" & name
        if fileExists(filename): removeFile(filename)
        result.memfile = memfiles.open(filename, fmReadWrite, newFileSize = size)
        result.data = cast[ptr T](result.memfile.mem)
    
    result.name    = name
    result.size    = size
    result.data[]  = default(T)
    result.isOwner = true

proc openObjectShm*[T](name : string) : ObjectShm[T] =
    when not T.isStaticType:
        raise newException(ValueError, "T must be a static type for ObjectShm")
    
    when defined(windows):
        let (handle, mem) = getSharedMemory(name, sizeof(T))
        result.data = cast[ptr T](mem)
        result.handle = handle
    else:
        let filename = "/dev/shm/" & name
        if not fileExists(filename): raise newException(ValueError, "File " & filename & " does not exist")
        result.memfile = memfiles.open(filename = filename, mode = fmReadWrite, mappedSize = sizeof(T))
        result.data = cast[ptr T](result.memfile.mem)
    
    result.name    = name
    result.size    = sizeof(T)
    result.isOwner = false

proc createMemFile*(name : string, size : int) : MemFile =
    let filename = "/dev/shm/" & name
    if fileExists(filename): removeFile(filename)
    if not dirExists(parentDir(filename)): createDir(parentDir(filename))
    result = memfiles.open(filename, fmReadWrite, newFileSize = size)

proc openMemFile*(name : string, size : int) : MemFile =
    let filename = "/dev/shm/" & name
    if not fileExists(filename): raise newException(ValueError, "File " & filename & " does not exist")
    result = memfiles.open(filename = filename, mode = fmReadWrite, mappedSize = size)

proc get*[T](self : ObjectShm[T]) : var T =
    return self.data[]

when isMainModule:
    type
        ABC* = object
            a* : StaticTable[2, StaticString[10], StaticString[10]]
    
    import tables, sequtils
    var
        writer = createObjectShm[ABC]("data")
        writerLookupTable = initTable[StaticString[10], int]()
        reader = openObjectShm[ABC]("data")
        readerLookupTable = initTable[StaticString[10], int]()
    echo writer.data[]
    writer.get().a.add("hello1".toStatic[:10], "world1".toStatic[:10], writerLookupTable)
    reader.get().a.add("hello2".toStatic[:10], "world2".toStatic[:10], readerLookupTable)
    echo writer.data[]
    echo reader.data[]
    echo Table[int, int].sizeof
    echo Table[StaticString[32], int].sizeof
    echo cast[array[ABC.sizeof, byte]](reader.get())