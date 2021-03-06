import std/[macros, genasts]
import std/[sequtils, dom, asyncjs]
import ajax

include shared


proc makeRequest*(url: string, data: string): Future[string] =
  return newPromise[string](proc(resolve: proc(response: string)) =
    var xhr = new_xmlhttp_request()

    if xhr.is_nil:
      echo "Giving up :( Cannot create an XMLHTTP instance"
      return

    proc onRecv(e:Event) =
      if xhr.readyState == rsDONE:
        if xhr.status == 200:
          resolve $xhr.responseText
        else:
          echo "There was a problem with the request."

    xhr.onreadystatechange = onRecv
    xhr.open("POST", url)
    xhr.send(data.cstring)
  )


# --- macros ----


# keep client
template client*(body: untyped): untyped = body

# on server just keep ajax procs for generating caller
macro server*(body: untyped): untyped =
  var ajaxProcs = newStmtList()
  for elem in
    case body.kind:
      of nnkStmtList:            body.toSeq
      of nnkProcDef, nnkFuncDef: @[body]
      else:                      @[]
  :
    if
      (elem.kind == nnkProcDef or elem.kind == nnkFuncDef) and
      elem.pragma.toSeq.anyIt(it.kind == nnkCall and it[0].strVal == "ajax")
    :
      ajaxProcs.add(elem)

  ajaxProcs


# make ajax callers
proc makeAjaxProc(app: NimNode, pathSeq: seq[string], procedure: NimNode): NimNode =
  let path = "/" & pathSeq.join("/")

  # proc for manipulating
  var editProc = procedure
  # if func turn into proc
  if procedure.kind == nnkFuncDef:
    editProc = newNimNode(nnkProcDef)
    for child in procedure: editProc.add(child)

  editProc.pragma = nnkPragma.newTree(ident("async"))

  var returnType = editProc.params[0]
  if returnType.kind == nnkBracketExpr and returnType[0].strVal == "Future":
    returnType = returnType[1]

  editProc.params[0] =
    if returnType.kind == nnkIdent:
      nnkBracketExpr.newTree(ident("Future"), returnType)
    else:
      newEmptyNode()

  # collect all param names into tuple for serializing for rpc later
  var paramTuple = newNimNode(nnkTupleConstr)
  for p in editProc.params.toSeq[1 .. ^1]:
    for p_ident in p.toSeq[0 ..< ^2]:
      paramTuple.add(p_ident)

  let procCall = genAst(path, paramTuple, returnType):
    fromJson(
      await makeRequest(path, toJson(paramTuple)),
      returnType
    )

  editProc.body = newStmtList(
    if returnType.kind == nnkIdent:
      nnkReturnStmt.newTree(procCall)
    else:
      procCall
  )

  editProc