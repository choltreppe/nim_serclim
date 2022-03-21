import serclim/private/common

import std/macros
import std/sequtils
import std/dom
import std/asyncjs
import ajax



proc makeRequest*(url: string, data: string): Future[string] =
  return newPromise[string](proc(resolve: proc(response: string)) =
    var xhr = new_xmlhttp_request()

    if xhr.is_nil:
      echo "Giving up :( Cannot create an XMLHTTP instance"
      return

    proc on_recv(e:Event) =
      if xhr.ready_state == rsDONE:
        if xhr.status == 200:
          resolve $xhr.response_text
        else:
          echo "There was a problem with the request."

    xhr.on_readystate_change = on_recv
    xhr.open("POST", url);
    xhr.send(data.cstring);
  )


# --- macros ----

const
  remote_pragma* = "ajax"


# keep client
template client*(body: untyped): untyped = body

# on server just keep ajax procs for generating caller
macro server*(body: untyped): untyped =
  var ajax_procs = newStmtList()
  for elem in
    case body.kind:
      of nnkStmtList:            body.toSeq
      of nnkProcDef, nnkFuncDef: @[body]
      else:                      @[]
  :
    if
      (elem.kind == nnkProcDef or elem.kind == nnkFuncDef) and
      elem.pragma.toSeq.anyIt(it.kind == nnkCall and it[0].strVal == remote_pragma)
    :
      ajax_procs.add(elem)

  return ajax_procs


# make ajax callers
macro ajax*(app: untyped, path: string, procedure: untyped): untyped =
  app.expectKind(nnkIdent)
  procedure.expectKind({nnkProcDef, nnkFuncDef})

  # proc for manipulating
  var proc_edit = procedure
  # if func turn into proc
  if procedure.kind == nnkFuncDef:
    proc_edit = newNimNode(nnkProcDef)
    for child in procedure: proc_edit.add(child)

  # remove pragma
  #[var new_pragma = newNimNode(nnkPragma)
  for p in proc_edit.pragma:
    if p.kind != nnkCall or p[0].strVal != remote_pragma:
      new_pragma.add(p)
  proc_edit.pragma = new_pragma]#
  proc_edit.pragma = nnkPragma.newTree(ident("async"))

  var return_type = proc_edit.params[0]
  if return_type.kind == nnkBracketExpr and return_type[0].strVal == "Future":
    return_type = return_type[1]

  proc_edit.params[0] =
    if return_type.kind == nnkIdent:
      nnkBracketExpr.newTree(ident("Future"), return_type)
    else:
      newEmptyNode()

  # collect all param names into tuple for serializing for rpc later
  var param_tuple = newNimNode(nnkTupleConstr)
  for p in proc_edit.params.toSeq[1 .. ^1]:
    for p_ident in p.toSeq[0 ..< ^2]:
      param_tuple.add(p_ident)

  # desirialize(await makeRequest({{path}}, serialize({{param tuple}}), {{return type}})
  let proc_call =
    ajaxDeserializeCall(
      newCall(ident("await"),
        newCall(ident("makeRequest"),
          path, ajaxSerializeCall(param_tuple)
        )
      ),
      return_type
    )

  proc_edit.body = newStmtList(
    if return_type.kind == nnkIdent:
      nnkReturnStmt.newTree(proc_call)
    else:
      proc_call
  )

  proc_edit