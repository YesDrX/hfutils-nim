import std/[options, atomics]

type
  RingBuffer*[N: static int, T] = object
    buffer: array[N, T]
    writeIdx: Atomic[int]
    readIdx: Atomic[int]
    count: Atomic[int]

proc initRingBuffer*[N: static int, T](): RingBuffer[N, T] =
  result.writeIdx.store(0, moRelaxed)
  result.readIdx.store(0, moRelaxed)
  result.count.store(0, moRelaxed)

proc tryPush*[N, T](rb: var RingBuffer[N, T], item: T): bool =
  let currentCount = rb.count.load(moAcquire)
  if currentCount >= N:
    return false
  
  let writePos = rb.writeIdx.load(moRelaxed)
  rb.buffer[writePos] = item

  let nextWritePos = (writePos + 1) mod N
  rb.writeIdx.store(nextWritePos, moRelease)
  
  discard rb.count.fetchAdd(1, moRelease)
  
  return true

proc tryPop*[N, T](rb: var RingBuffer[N, T], item: var T): bool =
  while true:
    var currentCount = rb.count.load(moAcquire)
    if currentCount <= 0:
      return false
    
    if not rb.count.compareExchange(currentCount, currentCount - 1, moAcquireRelease, moAcquire):
      continue
    
    while true:
      var currentReadIdx = rb.readIdx.load(moAcquire)
      let nextReadIdx = (currentReadIdx + 1) mod N
      
      if rb.readIdx.compareExchange(currentReadIdx, nextReadIdx, moAcquireRelease, moAcquire):
        item = rb.buffer[currentReadIdx]
        return true

proc spinPush*[N, T](rb: var RingBuffer[N, T], item: T) =
  while not rb.tryPush(item):
    cpuRelax()

proc isFull*[N, T](rb: var RingBuffer[N, T]): bool =
  rb.count.load(moAcquire) >= N

proc isEmpty*[N, T](rb: var RingBuffer[N, T]): bool =
  rb.count.load(moAcquire) <= 0

proc len*[N, T](rb: var RingBuffer[N, T]): int =
  rb.count.load(moAcquire)
