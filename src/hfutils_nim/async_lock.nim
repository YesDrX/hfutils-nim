#TODO: 
# - starvation: some task may wait forever if another task never releases the lock
# - memory ordering


import std/[atomics, locks]
import std/asyncdispatch

type
    AsyncLock* = ref object
        locked: Atomic[bool]

proc newAsyncLock*(): AsyncLock =
  result = AsyncLock()
  result.locked.store(false, moRelaxed)

proc tryAcquire*(self: AsyncLock): bool =
  var expected = false
  result = self.locked.compareExchange(expected, true, moAcquireRelease, moRelaxed)

proc acquire*(self: AsyncLock, timeoutSeconds: int): Future[void] {.async.} =
    var failCount = 0
    while not self.tryAcquire():
        failCount += 1
        if failCount div 1000  >= timeoutSeconds:
            raise newException(ValueError, "AsyncLock timed out")
        await sleepAsync(1) # Yield 1 millisecond to avoid high CPU usage

proc release*(self: AsyncLock) =
    if not self.locked.load(moRelaxed):
        raise newException(ValueError, "AsyncLock is not locked")
    self.locked.store(false, moRelease)
