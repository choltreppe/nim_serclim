import serclim/private/common

import jsony
import std/[macros, genasts]
import std/[sequtils, strutils]

import fusion/matching
{.experimental: "caseStmtMacros".}


type
  AnyInt   =  int |  int8 |  int16 |  int32 |  int64
  AnyUInt  = uint | uint8 | uint16 | uint32 | uint64
  AnyFloat = float | float32 | float64
  Json*[T] = T
  Body*[T] = T
  Form*[T] = T

func parseParam*[T: string  ](s: string, _: typedesc[T]): T = s

func parseParam*[T: AnyInt  ](s: string, _: typedesc[T]): T = s.parseInt.T

func parseParam*[T: AnyUInt ](s: string, _: typedesc[T]): T = s.parseUInt.T

func parseParam*[T: AnyFloat](s: string, _: typedesc[T]): T = s.parseFloat.T

func parseParam*[T: range   ](s: string, _: typedesc[T]): T = s.parseInt.T
template parseParam*(s: string, r: HSlice): untyped = parseParam(s, range[r])

func parseParam*[T: enum    ](s: string, _: typedesc[T]): T = parseEnum[T](s)

# patentialy marked with tranparent type marker
macro parseParamMarked(s: string, t: untyped): untyped =
  if t.kind == nnkBracketExpr and cmpIgnoreStyle(t[0].strVal, "Json") == 0:
    genAst(s, t = t[1]): fromJson(s, t)
  else:
    genAst(s, t): parseParam(s, t)


proc parseForm*[T: object](s: string, _: typedesc[T]): T =
  var strValTable: Table[string, string]
  for pairStr in s.split("&"):
    let pair = pairStr.split("=")
    strValTable[pair[0]] = pair[1]
  for name, val in result.fieldPairs:
    if name in strValTable:
      val = parseParam(strValTable[name], type(val))



macro route*(app: untyped, route: string, meth: untyped, procedure: untyped): untyped =
  procedure.expectKind({nnkProcDef, nnkFuncDef})

  func paramIdent   (pname: NimNode): NimNode = ident("param" & pname.strVal)
  func paramIdentStr(pname: NimNode): NimNode = ident("str"   & pname.strVal)

  let
    symBody = genSym(nskParam, "body")
    symQueryStr = genSym(nskParam, "queryStr")
    symCookieJar = genSym(nskVar, "cookieJar")

  # ---- gen routing pattern ----

  var editRoute = route.strVal

  if editRoute[0] == '/':
    editRoute.delete(0 .. 0)

  if editRoute.len >= 1 and editRoute[^1] == '/':
    editRoute = editRoute[0 ..< ^1]

  let routeElems = editRoute.split('/')

  var routingPattern = newNimNode(nnkBracket)
  var routeParams: seq[string]
  for relem in routeElems:
    routingPattern.add(
      if editRoute.len >= 2 and relem[0] == '@':
        let param = relem[1 .. ^1]
        routeParams.add(param)
        nnkPrefix.newTree(ident("@"), ident(param).paramIdentStr)
      else:
        newStrLitNode(relem)
    )

  # ---- gen type casting for params  &  proc call ----

  var procCall = newCall(procedure.name)
  
  var needsCookies = false
  
  let paramIdents =
    if procedure.params.len <= 1: newStmtList()  # in case of no parameters no typecasting is needed
    else:

      var paramParsing = newNimNode(nnkTupleConstr)  # tuple of params casted to correct type
      var paramAssign = newNimNode(nnkVarTuple)      # assigning those

      # collecting everything for type casting and proc call
      for p in procedure.params[1 .. ^1]:
        let ptype =
          if p[^2].kind != nnkEmpty: p[^2]
          else: typeOfLit(p[^1])
        for pname in p[0 ..< ^2]:
          if routeParams.contains(pname.strVal):
            paramParsing.add:
              genAst(pname = pname.paramIdentStr, ptype):
                parseParamMarked(pname, ptype)

          elif ptype.kind == nnkBracketExpr and cmpIgnoreStyle(ptype[0].strVal, "Body") == 0:
            paramParsing.add:
              genAst(symBody, ptype = ptype[1]):
                parseParamMarked(symBody, ptype)

          elif ptype.kind == nnkBracketExpr and cmpIgnoreStyle(ptype[0].strVal, "Form") == 0:
            paramParsing.add:
              genAst(symBody, symQueryStr, meth, ptype = ptype[1]):
                parseForm(
                  when meth == HttpPost: symBody
                  else:                  symQueryStr 
                  ,
                  ptype
                )
            
          elif
            (ptype.kind == nnkIdent and cmpIgnoreStyle(ptype.strVal, "CookieJar") == 0) or
            (ptype.kind == nnkVarTy and cmpIgnoreStyle(ptype[0].strVal, "CookieJar") == 0)
          :
            procCall.add(nnkExprEqExpr.newTree(pname, symCookieJar))
            needsCookies = true
            continue

          else: continue
          paramAssign.add(pname.paramIdent)
          procCall.add(nnkExprEqExpr.newTree(pname, pname.paramIdent))  # using explicit names to account for defaults

      if paramAssign.len == 0: newStmtList()
      else:
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
    procCall = genAst(procCall): await procCall
    returnType = returnType[1]

  if returnType.strVal == "string":
    procCall = genAst(procCall): respText(Http200, procCall)
  elif returnType.strVal != "Response":
    error "return type needs to be one of: Response, Future[Response], string, Future[string]"
    return

  # ---- add handler to app ----

  let addHandler =
    if needsCookies:
      genAst(app, methVal = meth, paramIdents, routingPattern, procCall, symBody, symQueryStr, symCookieJar):
        app.handlers.add(proc(meth: HttpMethod, path: seq[string], symBody, symQueryStr, cookieStr: string): Future[Option[Response]] {.async.} =
          if meth == methVal:
            if routingPattern ?= path:
              var symCookieJar = parseCookies(cookieStr)
              paramIdents
              var resp = procCall
              resp.headers = resp.headers.withCookies(symCookieJar)
              return some(resp)
          return none(Response)
        )
    else:
      genAst(app, methVal = meth, paramIdents, routingPattern, procCall, symBody, symQueryStr):
        app.handlers.add(proc(meth: HttpMethod, path: seq[string], symBody, symQueryStr, cookieStr: string): Future[Option[Response]] {.async.} =
          if meth == methVal:
            if routingPattern ?= path:
              paramIdents
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
  let symBody = genSym(nskParam, "body")


  var pathSeq = path.strVal[1 .. ^1].split('/')
  var pathPattern = newNimNode(nnkBracket)
  for elem in 
    if pathSeq[^1] == "": pathSeq[0 ..< ^1]
    else: pathSeq
  : pathPattern.add(newStrLitNode(elem))


  # ---- gen type casting for params & proc call ----

  var procCall = newCall(procedure.name)

  let paramIdents =
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

      nnkLetSection.newTree(
        paramAssign.add(
          newEmptyNode(),
          block: genAst(symBody, paramParsing):
            try: fromJson(symBody, paramParsing)
            except: return none(Response)
        )
      )

  # if proc returns Future need await call
  let returnType = procedure.params[0]
  if returnType.kind == nnkBracketExpr and returnType[0].strVal == "Future":
    procCall = genAst(procCall): await procCall
  procCall = genAst(procCall): toJson(procCall)


  # ---- add handler to app ----

  let addHandler = genAst(app, methVal = meth, paramIdents, pathPattern, procCall, symBody):
    app.handlers.add(proc(meth: HttpMethod, path: seq[string], symBody: string, queryStr,cookieStr: string): Future[Option[Response]] {.async.} =
      if methVal == meth and path == pathPattern:
        paramIdents
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