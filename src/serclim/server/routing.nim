import serclim/private/common

import std/macros
import std/sequtils
import std/strutils

import fusion/matching
{.experimental: "caseStmtMacros".}


# generate call to add handler lambda to app.handlers
proc genAddHandler(app: NimNode, body: NimNode): NimNode =
  newCall(ident("add"),
    newDotExpr(app, ident("handlers")),
    nnkLambda.newTree(
      newEmptyNode(), newEmptyNode(), newEmptyNode(),
      nnkFormalParams.newTree(
        nnkBracketExpr.newTree(ident("Future"), nnkBracketExpr.newTree(ident("Option"), ident("Response"))),
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

  var route_edit = route.strVal
  if route_edit[0] == '/':
    route_edit.delete(0 .. 0)

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

  if open: routing_pattern.add(prefix(ident("_"), ".."))


  # ---- gen type casting for params  &  proc call ----

  var proc_call = newCall(procedure.name)
  
  let parsed_params =
    if procedure.params.len <= 1: newStmtList()  # in case of no parameters no typecasting is needed
    else:

      var param_parsing = newNimNode(nnkTupleConstr)  # tuple of params casted to correct type
      var param_assign = newNimNode(nnkVarTuple)        # assigning those
      
      # collecting everything for type casting and proc call
      for p in procedure.params.toSeq[1 .. ^1]:
        let ptype = p[^2]
        for pname in p[0 ..< ^2]:

          param_assign.add(pname)
          param_parsing.add(
            if ptype.strVal == "string":
              pname.unparsedParam
            elif ptype.strVal.startsWith("int"):
              newCall(ptype, newCall(ident("parseInt"), pname.unparsedParam))
            elif ptype.strVal.startsWith("uint") :
              newCall(ptype, newCall(ident("parseUint"), pname.unparsedParam))
            elif ptype.strVal.startsWith("float") :
              newCall(ptype, newCall(ident("parseFloat"), pname.unparsedParam))
            else:
              error("routing parameters don't support " & ptype.strVal)
              return
          )

          proc_call.add(pname)

      #[  let parsed_params = nnkLetSection.newTree(
        param_assign.add(
          newEmptyNode(),
          quote do:
            try: `param_parsing`
            except: return none(string)
        )
      ) ]#
      # assign casted types. if not possible route failed
      nnkLetSection.newTree(
        param_assign.add(
          newEmptyNode(),
          nnkTryStmt.newTree(
            newStmtList(param_parsing),
            nnkExceptBranch.newTree(newStmtList(
              nnkReturnStmt.newTree(
                newCall(ident("none"), ident("Response"))
              )
            ))
          )
        )
      )

  var return_type = procedure.params[0]

  if return_type.kind == nnkBracketExpr and return_type[0].strVal == "Future":
    proc_call = newCall(ident("await"), proc_call)
    return_type = return_type[1]

  if return_type.strVal == "string":
    proc_call = newCall(ident("respText"), ident("Http200"), proc_call)
  elif return_type.strVal != "Response":
    error "return type needs to be one of: Response, Future[Response], string, Future[string]"
    return


  # ---- add handler to app ----
  
  #[ let add_route = quote do:
    `app`.routes.add(proc(meth: HttpMethod, path: seq[string], body: string): Future[Option[string]] =
      if meth == `meth`:
        if `routing_pattern` ?= path:
          `parsed_params`
          return some(`proc_call`)
      return none(string)
    ) ]#
  let add_handler = genAddHandler(app,
    newStmtList(
      newIfStmt((infix(ident("meth"), "==", meth), newStmtList(
        newIfStmt((infix(routing_pattern, "?=", ident("path")), newStmtList(
          parsed_params,
          nnkReturnStmt.newTree(newCall(ident("some"), proc_call))
        )))
      ))),
      nnkReturnStmt.newTree(newCall(ident("none"), ident("Response")))
    )
  )

  newStmtList(procedure, add_handler)


proc genRoutePragma(app, route, procedure: NimNode, meth: string): NimNode =
  procedure.expectKind({nnkProcDef, nnkFuncDef})
  let route_pragma = newCall(ident("route"), app, route, ident(meth))
  var edit_procedure = procedure
  edit_procedure.pragma = 
    if edit_procedure.pragma.kind == nnkEmpty:
      nnkPragma.newTree(route_pragma)
    else:
      edit_procedure.pragma.add(route_pragma)
  edit_procedure

macro get*(app: untyped, route: string, procedure: untyped): untyped =
  genRoutePragma(app, route, procedure, "HttpGet")

macro post*(app: untyped, route: string, procedure: untyped): untyped =
  genRoutePragma(app, route, procedure, "HttpPost")



macro ajax*(app: untyped, path: string, procedure: untyped): untyped =
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

  let parsed_params =
    if procedure.params.len <= 1: newStmtList()  # in case of no parameters no typecasting is needed
    else:

      var param_parsing = newNimNode(nnkTupleConstr)
      var param_assign = newNimNode(nnkVarTuple)

      var j: int
      for p in procedure.params.toSeq[1 .. ^1]:
        for _ in 0 ..< p.len-2:
          param_parsing.add(p[^2])
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
            newStmtList(ajaxDeserializeCall(ident("body"), param_parsing)),
            nnkExceptBranch.newTree(newStmtList(
              nnkReturnStmt.newTree(
                newCall(ident("none"), ident("Response"))
              )
            ))
          )
        )
      )

  # if proc returns Future need await call
  let return_type = procedure.params[0]
  if return_type.kind == nnkBracketExpr and return_type[0].strVal == "Future":
    proc_call = newCall(ident("await"), proc_call)


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
        parsed_params,
        nnkReturnStmt.newTree(
          newCall(ident("some"),
            newCall(ident("respText"), ident("Http200"), ajaxSerializeCall(proc_call))
          )
        )
      ))),
      nnkReturnStmt.newTree(newCall(ident("none"), ident("Response")))
    )
  )

  # return original proc and the call to add route to app
  newStmtList(procedure, add_handler)


#[var ajax_anonymous_index {.compiletime.} = 0

macro ajax*(app: untyped, procedure: untyped): untyped =
  procedure.expectKind({nnkProcDef, nnkFuncDef})
  let ajax_pragma = newCall(ident("ajax"), app, newStrLitNode("ajax_call_" & $ajax_anonymous_index))
  ajax_anonymous_index += 1
  var edit_procedure = procedure
  edit_procedure.pragma = 
    if edit_procedure.pragma.kind == nnkEmpty:
      nnkPragma.newTree(ajax_pragma)
    else:
      edit_procedure.pragma.add(ajax_pragma)
  edit_procedure
]#