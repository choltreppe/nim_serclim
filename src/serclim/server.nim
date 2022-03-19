import std/options
import std/sequtils
import std/strutils
import std/asynchttpserver
import std/asyncdispatch

export strutils, options, asyncdispatch


type
  ServerApp* = object
    port: int
    handlers*: seq[proc(meth: HttpMethod, path: seq[string], body: string): Future[Option[string]] {.async, closure.}]
  Body*[T] = T

func newServerApp*(port = 8080): ServerApp =
  ServerApp(port: port)

proc run*(app: ServerApp) =
  proc loop {.async.} =
    var server = newAsyncHttpServer()
    proc cb(req: Request) {.async, gcsafe.} =
      echo req.url.path

      let headers = {"Content-type": "text/html; charset=utf-8"}
      let path = req.url.path[1 .. ^1].split('/')

      for i in 0 ..< app.handlers.len:
        if Some(@res) ?= await app.handlers[i](req.reqMethod, path, req.body):
          await req.respond(Http200, res, headers.newHttpHeaders())
          return

      await req.respond(Http404, "Page not found", headers.newHttpHeaders())

    server.listen(Port(app.port))
    while true:
      if server.shouldAcceptRequest():
        await server.acceptRequest(cb)
      else:
        # too many concurrent connections, `maxFDs` exceeded
        # wait 500ms for FDs to be closed
        await sleepAsync(500)

  waitFor loop()



# ---- macros ----


# ignore client. keep server
macro client*(_: untyped): untyped = discard
macro server*(body: untyped): untyped = body


# generate call to add handler lambda to app.handlers
proc genAddHandler(app: NimNode, body: NimNode): NimNode =
  newCall(ident("add"),
    newDotExpr(app, ident("handlers")),
    nnkLambda.newTree(
      newEmptyNode(), newEmptyNode(), newEmptyNode(),
      nnkFormalParams.newTree(
        nnkBracketExpr.newTree(ident("Future"), nnkBracketExpr.newTree(ident("Option"), ident("string"))),
        nnkIdentDefs.newTree(ident("meth"), ident("HttpMethod"), newEmptyNode()),
        nnkIdentDefs.newTree(ident("path"), nnkBracketExpr.newTree(ident("seq"), ident("string")), newEmptyNode()),
        nnkIdentDefs.newTree(ident("body"), ident("string"), newEmptyNode())
      ),
      nnkPragma.newTree(ident("async")),
      newEmptyNode(),
      body
    )
  )


macro route*(app: untyped, route: string, meth: untyped, procedure: untyped): untyped =
  procedure.expectKind({nnkProcDef, nnkFuncDef})

  # generate ident for unparsed raw string param
  func unparsedParam(pname: NimNode): NimNode = ident(pname.strVal & "_str")


  # ---- gen routing pattern ----

  var route_edit = route.strVal[1 .. ^1]

  let open =
    if route_edit.len >= 1 and route_edit[^1] == '*':
      route_edit = route_edit[0 ..< ^1]
      true
    else: false

  if route_edit.len >= 1 and route_edit[^1] == '/':
    route_edit = route_edit[0 ..< ^1]

  let route_elems = route_edit.split('/')

  var routing_pattern = newNimNode(nnkBracket)
  for relem in route_elems:
    routing_pattern.add(
      if route_edit.len >= 2 and relem[0] == '{' and relem[^1] == '}':
        nnkPrefix.newTree(ident("@"), ident(relem[1 ..< ^1]).unparsedParam)
      else:
        newStrLitNode(relem)
    )


  # ---- gen type casting for params & proc call ----

  var proc_call = newCall(procedure.name)
  
  let typed_params =
    if procedure.params.len <= 1: newStmtList()  # in case of no parameters no typecasting is needed
    else:

      var param_type_cast = newNimNode(nnkTupleConstr)  # tuple of params casted to correct type
      var param_assign = newNimNode(nnkVarTuple)        # assigning those
      
      # collecting everything for type casting and proc call
      for p in procedure.params.toSeq[1 .. ^1]:
        let ptype = p[^2]
        for pname in p[0 ..< ^2]:

          param_assign.add(pname)
          param_type_cast.add(
            if ptype.strVal == "string":
              pname.unparsedParam
            elif ptype.strVal.startsWith("int"):
              newCall(ptype, newCall(ident("parseInt"), pname.unparsedParam))
            elif ptype.strVal.startsWith("uint") :
              newCall(ptype, newCall(ident("parseUint"), pname.unparsedParam))
            elif ptype.strVal.startsWith("float") :
              newCall(ptype, newCall(ident("parseFloat"), pname.unparsedParam))
            else:
              raise Exception.newException("unsuported type")
          )

          proc_call.add(pname)

      #[  let typed_params = nnkLetSection.newTree(
        param_assign.add(
          newEmptyNode(),
          quote do:
            try: `param_type_cast`
            except: return none(string)
        )
      ) ]#
      # assign casted types. if not possible route failed
      nnkLetSection.newTree(
        param_assign.add(
          newEmptyNode(),
          nnkTryStmt.newTree(
            newStmtList(param_type_cast),
            nnkExceptBranch.newTree(newStmtList(
              nnkReturnStmt.newTree(
                newCall(ident("none"), ident("string"))
              )
            ))
          )
        )
      )


  # ---- add handler to app ----
  
  #[ let add_route = quote do:
    `app`.routes.add(proc(meth: HttpMethod, path: seq[string], body: string): Future[Option[string]] =
      if meth == `meth`:
        if `routing_pattern` ?= path:
          `typed_params`
          return some(`proc_call`)
      return none(string)
    ) ]#
  let add_handler = genAddHandler(app,
    newStmtList(
      newIfStmt((infix(ident("meth"), "==", meth), newStmtList(
        newIfStmt((infix(routing_pattern, "?=", ident("path")), newStmtList(
          typed_params,
          nnkReturnStmt.newTree(newCall(ident("some"), proc_call))
        )))
      ))),
      nnkReturnStmt.newTree(newCall(ident("none"), ident("string")))
    )
  )


  newStmtList(procedure, add_handler)



macro ajax*(app: untyped, path: string, procedure: untyped): untyped =
  app.expectKind(nnkIdent)
  procedure.expectKind({nnkProcDef, nnkFuncDef})

  # for now always POST. probably later choosable
  let meth = ident("HttpPost")


  var path_seq = path.strVal[1 .. ^1].split('/')
  var path_pattern = newNimNode(nnkBracket)
  for elem in 
    if path_seq[^1] == "": path_seq[0 ..< ^1]
    else: path_seq
  : path_pattern.add(newStrLitNode(elem))


  # ---- gen type casting for params & proc call ----

  var proc_call = newCall(procedure.name)

  let typed_params =
    if procedure.params.len <= 1: newStmtList()  # in case of no parameters no typecasting is needed
    else:

      var param_type_cast = newNimNode(nnkTupleConstr)
      var param_assign = newNimNode(nnkVarTuple)

      var j: int
      for p in procedure.params.toSeq[1 .. ^1]:
        for _ in 0 ..< p.len-2:
          param_type_cast.add(p[^2])
          let param = ident("param" & $j)
          param_assign.add(param)
          proc_call.add(param)
          j += 1

      #[
        {{param tuple}} =
          try: deserialize(body, {{type tuple}})
          except: return none(string)
      ]#
      nnkLetSection.newTree(
        param_assign.add(
          newEmptyNode(),
          nnkTryStmt.newTree(
            newStmtList(deserializeCall(ident("body"), param_type_cast)),
            nnkExceptBranch.newTree(newStmtList(
              nnkReturnStmt.newTree(
                newCall(ident("none"), ident("string"))
              )
            ))
          )
        )
      )

  # ---- add handler to app ----

  #[
    add({{app}}.handlers, proc(meth: HttpMethod, path: seq[string], body: string): Future[Option[string]] {.async.} =
      if meth == {{method}} and path == {{path seq}}:
        let (param1, param2 ...) =
          try: deserialize(body, (type1, type2 ...))
          except: return none(string)
        return some(serialize({{proc}}(param1, param2 ...)))
      return none(string)
    )
  ]#
  let add_handler = genAddHandler(app,
    newStmtList(
      newIfStmt((infix(
        infix(ident("meth"), "==", meth), "and",
        infix(ident("path"), "==", path_pattern)),
      newStmtList(
        typed_params,
        nnkReturnStmt.newTree(newCall(ident("some"), serializeCall(proc_call)))
      ))),
      nnkReturnStmt.newTree(newCall(ident("none"), ident("string")))
    )
  )

  # return original proc and the call to add route to app
  newStmtList(procedure, add_handler)
