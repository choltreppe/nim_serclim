import serclim/private/common

import std/macros
import std/genasts
import std/sequtils
import std/strutils
import std/marshal
export marshal

import fusion/matching
{.experimental: "caseStmtMacros".}


type
  Body*[T] = T
  Json*[T] = T


macro route*(app: untyped, route: string, meth: untyped, procedure: untyped): untyped =
  procedure.expectKind({nnkProcDef, nnkFuncDef})

  # generate ident for unparsed raw string param
  func unparsedParam(pname: NimNode): NimNode = ident(pname.strVal & "_str")

  let
    handlerMeth = genSym(nskParam, "meth")
    handlerPath = genSym(nskParam, "path")
    handlerBody = genSym(nskParam, "body")

  # ---- gen routing pattern ----

  var editRoute = route.strVal
  if editRoute[0] == '/':
    editRoute.delete(0 .. 0)

  let open =
    if editRoute.len >= 1 and editRoute[^1] == '*':
      editRoute = editRoute[0 ..< ^1]
      true
    else: false

  if editRoute.len >= 1 and editRoute[^1] == '/':
    editRoute = editRoute[0 ..< ^1]

  let routeElems = editRoute.split('/')

  var routingPattern = newNimNode(nnkBracket)
  var routeParams: seq[string]
  for relem in routeElems:
    routingPattern.add(
      if editRoute.len >= 2 and relem[0] == '{' and relem[^1] == '}':
        let param = relem[1 ..< ^1]
        routeParams.add(param)
        nnkPrefix.newTree(ident("@"), ident(param).unparsedParam)
      else:
        newStrLitNode(relem)
    )

  if open: routingPattern.add(prefix(ident("_"), ".."))

  # ---- gen type casting for params  &  proc call ----

  var procCall = newCall(procedure.name)
  
  let parsedParams =
    if procedure.params.len <= 1: newStmtList()  # in case of no parameters no typecasting is needed
    else:

      var paramParsing = newNimNode(nnkTupleConstr)  # tuple of params casted to correct type
      var paramAssign = newNimNode(nnkVarTuple)      # assigning those
      
      proc parseBasicTypes(ptype, pname: NimNode): NimNode =
        if ptype.kind == nnkBracketExpr and ptype[0].strVal == "Json":
          genAst(handlerBody, t = ptype[1]):
            to[t](handlerBody)
        elif ptype.kind == nnkIdent:
          if ptype.strVal == "string": pname
          else:
            newCall(ptype, newCall(ident(
              if   ptype.strVal.startsWith("int")   : "parseInt"
              elif ptype.strVal.startsWith("uint")  : "parseUint"
              elif ptype.strVal.startsWith("float") : "parseFloat"
              else:
                error("routing parameters don't support " & ptype.strVal)
                return
              ),
              pname
            ))
        else:
          error("routing parameters don't support this type")
          return

      # collecting everything for type casting and proc call
      for p in procedure.params[1 .. ^1]:
        let ptype =
          if p[^2].kind != nnkEmpty: p[^2]
          else: typeOfLit(p[^1])
        for pname in p[0 ..< ^2]:
          if routeParams.contains(pname.strVal):
            paramParsing.add(parseBasicTypes(ptype, pname.unparsedParam))
          #[elif ptype.kind == nnkBracketExpr and ptype[0].strVal == "Json":
            paramParsing.add(
              genAst(handlerBody, t = ptype[1]):
                to[t](handlerBody)
            )]#
          elif ptype.kind == nnkBracketExpr and ptype[0].strVal == "Body":
            paramParsing.add(parseBasicTypes(ptype[1], handlerBody))

          else: continue
          paramAssign.add(pname)
          procCall.add(nnkExprEqExpr.newTree(pname, pname))  # using explicit names to account for defaults

      echo procedure.name.strVal
      echo paramParsing.treeRepr

      # assign casted types. if not possible route failed
      nnkLetSection.newTree(
        paramAssign.add(
          newEmptyNode(),
          block:
            genAst(paramParsing):
              try: paramParsing
              except: return none(Response)
        )
      )

  var returnType = procedure.params[0]

  if returnType.kind == nnkBracketExpr and returnType[0].strVal == "Future":
    procCall = newCall(ident("await"), procCall)
    returnType = returnType[1]

  if returnType.strVal == "string":
    procCall = newCall(ident("respText"), ident("Http200"), procCall)
  elif returnType.strVal != "Response":
    error "return type needs to be one of: Response, Future[Response], string, Future[string]"
    return

  # ---- add handler to app ----

  let addHandler = genAst(app, meth, parsedParams, routingPattern, procCall, handlerMeth, handlerPath, handlerBody):
    app.handlers.add(proc(handlerMeth: HttpMethod, handlerPath: seq[string], handlerBody: string): Future[Option[Response]] {.async.} =
      if handlerMeth == meth:
        if routingPattern ?= handlerPath:
          parsedParams
          return some(procCall)
      return none(Response)
    )

  newStmtList(procedure, addHandler)



proc genRoutePragma(app, route, procedure: NimNode, meth: string): NimNode =
  procedure.expectKind({nnkProcDef, nnkFuncDef})
  let routePragma = newCall(ident("route"), app, route, ident(meth))
  var editProcedure = procedure
  editProcedure.pragma = 
    if editProcedure.pragma.kind == nnkEmpty:
      nnkPragma.newTree(routePragma)
    else:
      editProcedure.pragma.add(routePragma)
  editProcedure

macro get*(app: untyped, route: string, procedure: untyped): untyped =
  genRoutePragma(app, route, procedure, "HttpGet")

macro post*(app: untyped, route: string, procedure: untyped): untyped =
  genRoutePragma(app, route, procedure, "HttpPost")




macro ajax*(app: untyped, path: string, procedure: untyped): untyped =
  procedure.expectKind({nnkProcDef, nnkFuncDef})

  # for now always POST. probably later choosable
  let meth = ident("HttpPost")

  # handler lambda param idents
  let
    handlerMeth = genSym(nskParam, "meth")
    handlerPath = genSym(nskParam, "path")
    handlerBody = genSym(nskParam, "body")


  var pathSeq = path.strVal[1 .. ^1].split('/')
  var pathPattern = newNimNode(nnkBracket)
  for elem in 
    if pathSeq[^1] == "": pathSeq[0 ..< ^1]
    else: pathSeq
  : pathPattern.add(newStrLitNode(elem))


  # ---- gen type casting for params & proc call ----

  var procCall = newCall(procedure.name)

  let parsedParams =
    if procedure.params.len <= 1: newStmtList()  # in case of no parameters no typecasting is needed
    else:

      var paramParsing = newNimNode(nnkTupleConstr)
      var paramAssign = newNimNode(nnkVarTuple)

      var j: int
      for p in procedure.params.toSeq[1 .. ^1]:
        for _ in 0 ..< p.len-2:
          paramParsing.add(p[^2])
          let param = ident("param" & $j)
          paramAssign.add(param)
          procCall.add(param)
          j += 1

      #[
        {{param tuple}} =
          try: deserialize(body, {{type tuple}})
          except: return none(string)
      ]#
      nnkLetSection.newTree(
        paramAssign.add(
          newEmptyNode(),
          nnkTryStmt.newTree(
            newStmtList(ajaxDeserializeCall(handlerBody, paramParsing)),
            nnkExceptBranch.newTree(newStmtList(
              nnkReturnStmt.newTree(
                newCall(ident("none"), ident("Response"))
              )
            ))
          )
        )
      )

  # if proc returns Future need await call
  let returnType = procedure.params[0]
  if returnType.kind == nnkBracketExpr and returnType[0].strVal == "Future":
    procCall = newCall(ident("await"), procCall)
  procCall = ajaxSerializeCall(procCall)


  # ---- add handler to app ----

  let addHandler = genAst(app, meth, parsedParams, pathPattern, procCall, handlerMeth, handlerPath, handlerBody):
    app.handlers.add(proc(handlerMeth: HttpMethod, handlerPath: seq[string], handlerBody: string): Future[Option[Response]] {.async.} =
      if handlerMeth == meth and handlerPath == pathPattern:
        parsedParams
        return some(respText(Http200, procCall))
      return none(Response)
    )

  # return original proc and the call to add route to app
  newStmtList(procedure, addHandler)

#[var ajax_anonymous_index {.compiletime.} = 0

macro ajax*(app: untyped, procedure: untyped): untyped =
  procedure.expectKind({nnkProcDef, nnkFuncDef})
  let ajax_pragma = newCall(ident("ajax"), app, newStrLitNode("ajax_call_" & $ajax_anonymous_index))
  ajax_anonymous_index += 1
  var editProcedure = procedure
  editProcedure.pragma = 
    if editProcedure.pragma.kind == nnkEmpty:
      nnkPragma.newTree(ajax_pragma)
    else:
      editProcedure.pragma.add(ajax_pragma)
  editProcedure
]#