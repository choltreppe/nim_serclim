import fusion/matching
{.experimental: "caseStmtMacros".}

import sequtils
import dom
import ajax



const
  remote_pragma* = "ajax"

  # name of callback parameter in generatet rpc proc
  callback_param_name = "rpc_callback"


template client*(body: untyped): untyped = body


proc makeRequest*(url: string, data: string, f: proc(x: string) {.closure.}) =
  var xhr = newXMLHttpRequest()

  if xhr.isNil:
    echo "Giving up :( Cannot create an XMLHTTP instance"
    return

  proc onRecv(e:Event) =
    if xhr.ready_state == rsDONE:
      if xhr.status == 200:
        f($xhr.response_text)
      else:
        echo "There was a problem with the request."

  xhr.on_readystate_change = onRecv
  xhr.open("POST", url)
  xhr.send(data.cstring)


macro server*(body: untyped): untyped =

  var remote_procs = newStmtList()

  proc generate_rpc_if_callable(stmt_e: NimNode) =
    if stmt_e.kind == nnkProcDef or stmt_e.kind == nnkFuncDef:
      case
        stmt_e.pragma.toSeq
        .filterIt(it.kind == nnkCall and it[0].strVal == remote_pragma)
      :
        of [@pragma]:

          pragma[2].expectKind(nnkStrLit)
          let remote_url = pragma[2]

          # proc for manipulating
          # if func turn into proc
          var remote_proc = stmt_e
          if stmt_e.kind == nnkFuncDef:
            remote_proc = newNimNode(nnkProcDef)
            for child in stmt_e: remote_proc.add(child)

          # remove pragma
          #[var new_pragma = newNimNode(nnkPragma)
          for p in remote_proc.pragma:
            if p.kind != nnkCall or p[0].strVal != remote_pragma:
              new_pragma.add(p)
          remote_proc.pragma = new_pragma]#
          remote_proc.pragma = newEmptyNode()

          # seperate params and return type
          let return_type = stmt_e.params[0]
          var in_params = stmt_e.params
          # set no return type
          in_params[0] = newEmptyNode()

          # collect all param names into tuple for serializing for rpc later
          var param_tuple = newNimNode(nnkTupleConstr)
          for p in in_params.toSeq[1 .. ^1]:
            for p_ident in p.toSeq[0 ..< ^2]:
              param_tuple.add(p_ident)

          # if proc had return type, contruct lambda param for callback
          if return_type.kind == nnkIdent:
            in_params.add(newIdentDefs(
              ident(callback_param_name),
              newNimNode(nnkProcTy).add(
                newNimNode(nnkFormalParams).add(
                  newEmptyNode(),
                  newIdentDefs(ident("x"), return_type)
                ),
                newEmptyNode()
              )
            ))
          remote_proc.params = in_params

          # constaruct body with rpc
          # (not using quote because it had some bugs)
          remote_proc.body =
            newCall(ident("makeRequest"),
              remote_url,
              serializeCall(param_tuple),
              newNimNode(nnkLambda).add(
                newEmptyNode(), newEmptyNode(), newEmptyNode(),
                newNimNode(nnkFormalParams).add(
                  newEmptyNode(),
                  newIdentDefs(ident("resp"), ident("string"))
                ),
                newEmptyNode(), newEmptyNode(),
                if return_type.kind == nnkIdent:
                  newStmtList().add(
                    newCall(ident(callback_param_name),
                      deserializeCall(
                        ident("resp"),
                        return_type
                      )
                    )
                  )
                else:
                  quote: discard
              )
            )

          remote_procs.add(remote_proc)

        of []:
          discard

        else:
          raise Exception.newException("too many " & remote_pragma & " definitions")


  case body.kind:
    of nnkStmtList:
      for stmt_e in body: generate_rpc_if_callable(stmt_e)
    of nnkProcDef, nnkFuncDef:
      generate_rpc_if_callable(body)
    else: discard
  
  remote_procs
