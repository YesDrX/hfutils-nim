import std/[memfiles, os, strformat, macros]
import ./static_types

export memfiles, static_types

when defined(windows):
    import std/winlean

type
    ObjectShm*[T] = object
        name*    : string
        data*    : ptr T
        size*    : int
        isOwner* : bool
        when defined(posix):
            memfile* : Memfile
        elif defined(windows):
            handle* : Handle

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
            let filename = "/dev/shm/" & writer.name
            if fileExists(filename):
                removeFile(filename)

proc createObjectShm*[T](name : string) : ObjectShm[T] =
    when not T.isStaticType:
        raise newException(ValueError, "T must be a static type for ObjectShm")
    
    when defined(windows):
        let (handle, mem) = createSharedMemory(name, sizeof(T))
        result.data = cast[ptr T](mem)
        result.handle = handle
    else:
        let filename = "/dev/shm/" & name
        if fileExists(filename): removeFile(filename)
        result.memfile = memfiles.open(filename, fmReadWrite, newFileSize = sizeof(T))
        result.data = cast[ptr T](result.memfile.mem)
    
    result.name = name
    result.size = sizeof(T)
    result.data[] = default(T)
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
    
    result.name = name
    result.size = sizeof(T)
    result.isOwner = false

proc get*[T](self : ObjectShm[T]) : var T =
    return self.data[]

when isMainModule:
    type
        ABC* = object
            a* : StaticTable[100, StaticString[32], StaticString[32]]
            b* : int
    
    import tables, sequtils
    var
        writer = createObjectShm[ABC]("data")
        writerLookupTable = initTable[StaticString[32], int]()
        reader = openObjectShm[ABC]("data")
        readerLookupTable = initTable[StaticString[32], int]()
    echo writer.data[]
    writer.get().a.add("hello1".toStatic[:32], "world1".toStatic[:32], writerLookupTable)
    reader.get().a.add("hello2".toStatic[:32], "world2".toStatic[:32], readerLookupTable)
    reader.get().b = 10
    echo writer.data[]
    echo reader.data[]