import std/[os, locks, macros, times, atomics, strformat, cpuinfo]

export os, locks, atomics, times, atomics, cpuinfo, strformat

# Ensure correct memory management for threads
when not defined(gcAtomicArc) and not defined(gcOrc):
    {.error: "Thread executor requires --mm:atomicArc or --mm:orc".}

type
    TaskStatus* = enum
        Pending, Running, Completed, Failed

    # Task object holding data, result, and exception
    Task*[T, R] = ref object
        id: int
        input*: T
        result*: R
        status*: TaskStatus
        exception*: ref Exception
        # Metrics
        createdTime*: DateTime
        startTime*: DateTime
        finishTime*: DateTime

    Executor*[T, R] = ref object
        fn: proc(arg: T): R {.gcsafe.}
        tasks*: seq[Task[T, R]]
        
        # Atomic Synchronization
        nextTaskIdx: Atomic[int]   
        tasksCompleted: Atomic[int]
        
        # Thread Management
        lock: Lock                 
        workAvailable: Cond        
        batchFinished: Cond        
        
        threads: seq[Thread[Executor[T, R]]]
        shutdown: bool             
        
        raiseOnException: bool     

# --- Forward Declarations ---
proc workerLoop[T, R](executor: Executor[T, R]) {.thread.}

# --- Constructor ---

proc newExecutor*[T, R](fn: proc(arg: T): R {.gcsafe.}, numThreads: int = countProcessors(), raiseOnException: bool = false): Executor[T, R] =
    new(result)
    result.fn = fn
    result.tasks = @[]
    result.shutdown = false
    result.raiseOnException = raiseOnException
    
    result.nextTaskIdx.store(0)
    result.tasksCompleted.store(0)
    
    initLock(result.lock)
    initCond(result.workAvailable)
    initCond(result.batchFinished)

    result.threads = newSeq[Thread[Executor[T, R]]](numThreads)
    
    for i in 0 ..< numThreads:
        createThread(result.threads[i], workerLoop[T, R], result)

# --- Public API ---

proc submit*[T, R](executor: Executor[T, R], arg: T) =
    let t = Task[T, R](
        id: executor.tasks.len,
        input: arg,
        status: Pending,
        createdTime: now()
    )
    executor.tasks.add(t)

proc run*[T, R](executor: Executor[T, R]) =
    if executor.tasks.len == 0:
        return

    executor.tasksCompleted.store(0)
    executor.nextTaskIdx.store(0)

    withLock(executor.lock):
        broadcast(executor.workAvailable)
        
        # Wait until ALL tasks are accounted for (completed or failed-and-thread-died)
        while executor.tasksCompleted.load() < executor.tasks.len:
            wait(executor.batchFinished, executor.lock)

proc clear*[T, R](executor: Executor[T, R]) =
    executor.tasks.setLen(0)

proc shutdown*[T, R](executor: Executor[T, R]) =
    withLock(executor.lock):
        executor.shutdown = true
        broadcast(executor.workAvailable)
    
    joinThreads(executor.threads)
    deinitLock(executor.lock)
    deinitCond(executor.workAvailable)
    deinitCond(executor.batchFinished)

# --- Internal Worker Logic ---

proc workerLoop[T, R](executor: Executor[T, R]) =
    {.gcsafe.}:
        while true:
            let myIdx = executor.nextTaskIdx.fetchAdd(1)

            if myIdx < executor.tasks.len:
                let task = executor.tasks[myIdx]
                
                # Wrap in try/finally to ensure metrics/signaling happen 
                # even if we raise an exception and kill the thread.
                try:
                    task.status = Running
                    task.startTime = now()
                    
                    try:
                        when R isnot void:
                            task.result = executor.fn(task.input)
                        else:
                            executor.fn(task.input)
                        task.status = Completed
                    except CatchableError as e:
                        task.status = Failed
                        task.exception = e

                        if executor.raiseOnException:
                            echo fmt"[Thread Executor] Thread {getThreadId()} failing on input: {task.input}"
                            echo fmt"[Thread Executor] Exception: {e.msg}"
                            # Re-raising here will abort the 'try', 
                            # but 'finally' block below will still run.
                            raise e
                    
                    task.finishTime = now()

                finally:
                    # CRITICAL: This block executes even if 'raise e' was called above.
                    
                    # If we crashed before setting finishTime, set it now
                    if not task.finishTime.isInitialized:
                        task.finishTime = now()

                    # Atomically increment counter so main thread doesn't hang
                    let completedCount = executor.tasksCompleted.fetchAdd(1) + 1
                    
                    if completedCount == executor.tasks.len:
                        withLock(executor.lock):
                            signal(executor.batchFinished)

            else:
                withLock(executor.lock):
                    if executor.shutdown: 
                        break
                    
                    while executor.nextTaskIdx.load() >= executor.tasks.len and not executor.shutdown:
                        wait(executor.workAvailable, executor.lock)
                    
                    if executor.shutdown: 
                        break

# --- convinient macros ---
proc procArgsToArgType(arg_type_name : string, proc_args : seq[NimNode]): NimNode =
    let arg_type = arg_type_name.newIdentNode()

    result = quote do:
        type `arg_type`* = object

    if proc_args.len > 0:
        result[0][2][2] = nnkRecList.newTree()
        for arg in proc_args:
            var argToAdd = arg
            argToAdd[0] = nnkPostfix.newTree(
                newIdentNode("*"),
                arg[0]
            )
            result[0][2][2].add(arg)

macro parallel*(proc_def : untyped): untyped =
    if proc_def.kind != nnkProcDef:
        raise newException(Exception, "parallel pragma can only be used on a proc definition")
    
    if proc_def[2].kind != nnkEmpty:
        raise newException(Exception, "parallel pragma can only be used on a proc definition with no generic parameters")
    
    let proc_name = proc_def[0].strVal
    let targ_name = fmt"TArg_{proc_name}"
    let trtn_name = fmt"TRtn_{proc_name}".newIdentNode

    let rtn_args = proc_def[3]
    let targ = procArgsToArgType(targ_name, rtn_args[1..^1])
    var trtn = block:
        echo rtn_args[0].treeRepr
        echo "****"
        if rtn_args[0].kind != nnkEmpty:
            fmt"type {trtn_name.strVal}* = {rtn_args[0].strVal}".parseStmt
        else:
            fmt"type {trtn_name.strVal}* = void".parseStmt

    result = quote do:
        `targ`

        `trtn`
        
        `proc_def`

    var arg_names : seq[string]
    for arg in rtn_args[1..^1]:
        for arg_name in arg[0..^3]:
            arg_names.add(arg_name.strVal)
    
    if arg_names.len > 1:
        # create a wrapper proc to pass to the executor
        let proc_name_ident = proc_name.newIdentNode
        let targ_name_ident = targ_name.newIdentNode
        let arg = "arg".newIdentNode
        var wrapper_proc = quote do:
            proc `proc_name_ident`*(`arg` : `targ_name_ident`): `trtn_name` = `proc_name_ident`()
        for arg_name in arg_names:
            wrapper_proc[6][0].add nnkDotExpr.newTree(
                arg,
                arg_name.newIdentNode
            )
        result.add wrapper_proc

        var submit_proc = fmt"""proc submit*(executor: Executor[{targ_name}, {trtn_name.strVal}]) = submit(executor)""".parseStmt()[0]

        for arg in proc_def[3][1..^1]:
            submit_proc[3].add arg
        
        submit_proc[6][0].add nnkObjConstr.newTree(
            targ_name.newIdentNode
        )
        for arg_name in arg_names:
            submit_proc[6][0][2].add nnkExprColonExpr.newTree(
                arg_name.newIdentNode,
                arg_name.newIdentNode
            )
        result.add submit_proc

    # echo result.repr

when isMainModule:
    # --- demo ---
    proc worker(name : string, idx : int = 0): bool {.parallel.} =
        echo name
        sleep(1000)

    var executor = newExecutor(worker, numThreads = 16)
    for i in 0..100:
        executor.submit(fmt"Worker {i}")
    executor.run()
    for task in executor.tasks:
        echo "Task ", task.id, " status: ", task.status, " result: ", task.result, " start: ", task.startTime.toTime.toUnix - task.createdTime.toTime.toUnix, " finish: ", task.finishTime.toTime.toUnix - task.startTime.toTime.toUnix
    executor.shutdown()