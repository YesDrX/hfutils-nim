import std/[memfiles, os]
import ./static_types

export memfiles, static_types

when defined(windows):
    {.error : "Windows is not supported".}

proc createMemFile*(name : string, size : int) : MemFile =
    let filename = "/dev/shm/" & name
    if fileExists(filename): removeFile(filename)
    if not dirExists(parentDir(filename)): createDir(parentDir(filename))
    result = memfiles.open(filename, fmReadWrite, newFileSize = size)

proc openMemFile*(name : string, size : int) : MemFile =
    let filename = "/dev/shm/" & name
    if not fileExists(filename): raise newException(ValueError, "File " & filename & " does not exist")
    result = memfiles.open(filename = filename, mode = fmReadWrite, mappedSize = size)
