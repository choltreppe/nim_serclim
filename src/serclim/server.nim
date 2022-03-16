import sequtils

import prologue
export prologue


macro client*(_: untyped): untyped = newStmtList()


macro server*(body: untyped): untyped = body


proc get_post(app: NimNode, route: NimNode, meth: string, body: NimNode): NimNode =
  body.expectKind({nnkProcDef, nnkFuncDef})
  newStmtList(
    newCall(ident("async"), body),
    newCall(ident("addRoute"), app, route, body[0], ident(meth))
  )

macro get*(app: untyped, route: untyped, body: untyped): untyped =
  get_post(app, route, "HttpGet", body)

macro post*(app: untyped, route: untyped, body: untyped): untyped =
  get_post(app, route, "HttpPost", body)


macro ajax*(app: untyped, route: string, body: untyped): untyped =
  app.expectKind(nnkIdent)
  body.expectKind({nnkProcDef, nnkFuncDef})

  var param_tuple_type = newNimNode(nnkTupleConstr)
  var param_tuple_assign = newNimNode(nnkVarTuple)

  var proc_call = newCall(body[0])

  var j: int
  for p in body.params.toSeq[1 .. ^1]:
    for _ in 0 ..< p.len-2:
      param_tuple_type.add(p[2])
      let param = ident("param" & $j)
      param_tuple_assign.add(param)
      proc_call.add(param)
      j += 1

  # {{param tuple}} = deserialize(ctx.request.body, {{type tuple}})
  param_tuple_assign.add(
    newEmptyNode(),
    deserializeCall(
      newDotExpr(newDotExpr(ident("ctx"), ident("request")), ident("body")),
      param_tuple_type
    )
  )

  #[
    app.post({{route}}, proc(ctx: Context) {.async.} =
      let {{param tuple}} = deserialize(ctx.request.body, {{type tuple}})
      resp serialize({{proc call}} {{params}})
    )
  ]#
  let app_route =
    newCall(ident"post").add(
      app,
      route,
      newNimNode(nnkLambda).add(
        newEmptyNode(), newEmptyNode(), newEmptyNode(),
        newNimNode(nnkFormalParams).add(
          newEmptyNode(),
          newIdentDefs(ident("ctx"), ident("Context"))
        ),
        newNimNode(nnkPragma).add(ident("async")),
        newEmptyNode(),
        newStmtList().add(
          newNimNode(nnkLetSection).add(param_tuple_assign),
          newCall(ident("resp"), serializeCall(proc_call))
        )
      )
    )

  # return original proc and the call to add route to app
  newStmtList(body, app_route)
