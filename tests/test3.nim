# async_lock_test.nim
import std/[atomics, locks, asyncdispatch, os, times, unittest, strutils, strformat]
import hfutils_nim/asyncLock

# ---------------------------------------------------------------------------
# 0.  Helper that gives every coroutine a unique name
# ---------------------------------------------------------------------------
var gTaskId: Atomic[int]
template taskName(prefix: string): string =
  prefix & $gTaskId.fetchAdd(1, moRelaxed)

# ---------------------------------------------------------------------------
# 1.  Basic “lock protects a counter” test
# ---------------------------------------------------------------------------
suite "correctness – single contention spot":
  test "1000 parallel increments must end up at 1000":
    var L = newAsyncLock()
    var counter = 0

    proc worker(): Future[void] {.async.} =
      await L.acquire(30)          # 30 s timeout – should never fire
      inc counter
      L.release()

    var futs: seq[Future[void]]
    for i in 1..1000:
      futs.add worker()
    waitFor all(futs)
    check counter == 1000

# ---------------------------------------------------------------------------
# 2.  Starvation detector
# ---------------------------------------------------------------------------
suite "starvation behaviour":
  test "one greedy task must not starve the others (detected via max wait time)":
    var L = newAsyncLock()
    const tasks = 10               # 10 polite tasks
    const greedyLoops = 100_000    # greedy task keeps lock 100 k times
    var maxWait: array[tasks, float] # seconds a polite task had to wait

    # Greedy coroutine – releases and immediately re-acquires
    proc greedy(): Future[void] {.async.} =
      for _ in 1..greedyLoops:
        await L.acquire(30)
        L.release()                # no sleep – will usually win the race

    # Polite coroutine – measures how long it takes to get the lock once
    proc polite(id: int): Future[void] {.async.} =
      let t0 = epochTime()
      await L.acquire(30)
      let t1 = epochTime()
      maxWait[id] = t1 - t0
      L.release()

    var futs: seq[Future[void]]
    futs.add greedy()
    for i in 0..<tasks:
      futs.add polite(i)
    waitFor all(futs)

    # If any polite task waited > 0.1 s we call that starvation
    for w in maxWait:
      check w < 0.1

# ---------------------------------------------------------------------------
# 3.  Time-out path
# ---------------------------------------------------------------------------
suite "timeout":
  test "acquire must raise after N seconds when lock is held":
    var L = newAsyncLock()
    waitFor L.acquire(30)          # holder never releases
    try:
      waitFor L.acquire(1)         # 1 s timeout
      check false                  # must not reach here
    except ValueError:
      discard                      # expected

# ---------------------------------------------------------------------------
# 4.  “Unlock without holding” must throw
# ---------------------------------------------------------------------------
suite "mis-use":
  test "release on free lock must raise":
    var L = newAsyncLock()
    expect ValueError:
      L.release()

# ---------------------------------------------------------------------------
# 5.  Memory-ordering stress (many threads, tiny critical section)
# ---------------------------------------------------------------------------
suite "memory ordering / atomicity":
  test "lock must serialize 64-bit counter updates across OS threads":
    var L = newAsyncLock()
    var
      hi, lo: Atomic[int64]
      threads: array[16, Thread[void]]

    proc threadBody {.thread.} =
      {.gcsafe.}:
        for _ in 1..50_000:
          waitFor L.acquire(30)
          discard lo.fetchAdd(1, moRelaxed)
          
          if lo.load(moRelaxed) mod 50_000 == 0:
            discard hi.fetchAdd(1, moRelaxed)

          let h = hi.load(moRelaxed)
          let l = lo.load(moRelaxed)
          doAssert l div 50_000 == h, fmt"l={l}, h={h}"

          L.release()

    for i in 0..<threads.len:
      createThread(threads[i], threadBody)
    for i in 0..<threads.len:
      joinThread(threads[i])
    
    check hi.load(moRelaxed) == 16
    check lo.load(moRelaxed) == 16 * 50_000