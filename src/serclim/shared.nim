import std/[strutils, strformat]


template getPathSeq(path: string): untyped =
  if path.len == 0 or path[0] != '/':
    error "paths must be absolute"
  let pathSeq = path[1 .. ^1].split('/')
  if pathSeq.len > 0 and pathSeq[0] == ajaxAnonymousPath:
    error fmt"routes starting with '{ajaxAnonymousPath}' are reserved for ananymous ajax procs"
  pathSeq


const ajaxAnonymousPath = "remotecall"

var ajaxAnonymousIndex {.compiletime.} = 0'u


proc makeAjaxProc(app: NimNode, pathSeq: seq[string], procedure: NimNode): NimNode

macro ajax*(app, procedure: untyped): untyped =
  procedure.expectKind({nnkProcDef, nnkFuncDef})
  makeAjaxProc(app, @[ajaxAnonymousPath, $ajaxAnonymousIndex], procedure)

macro ajax*(app, path, procedure: untyped): untyped =
  procedure.expectKind({nnkProcDef, nnkFuncDef})
  path.expectKind(nnkStrLit)
  let pathSeq = path.strVal.getPathSeq
  makeAjaxProc(app, pathSeq, procedure)