import unittest
import serclim
import serclim/server/cookies
{.experimental: "caseStmtMacros".}



var app = newServerApp()


proc testRoutes(meth: HttpMethod, path: seq[string], body, queryStr = "", cookieStr = "", expectText: string, expectHeaders: RespHeaders = @[]): bool =
  for id in 0 ..< app.handlers.len:
    if Some(@res) ?= waitFor(app.handlers[id](meth, path, body, queryStr, cookieStr)):
      return res.kind == respOther and res.text == expectText and res.headers == expectHeaders
  false

proc testRouteNone(id: uint, meth: HttpMethod, path: seq[string]): bool =
  case waitFor(app.handlers[id](meth, path, "", "", "")):
    of None(Response): true
    else:              false



func testRoutePragma(p1,p2: string): string {.route(app, "/routepragma/@p1/@p2", HttpGet).} =
  "p1: " & p1 & ", p2: " & p2

test "routing: route pragma":
  check testRoutes(HttpGet, @["routepragma", "test1", "test2"], expectText = "p1: test1, p2: test2")
  check testRouteNone(0, HttpGet, @["routepragma", "test"])



func testGet(a,b: string): string {.get(app, "/testget/@a/@b").} =
  "a: " & a & ", b: " & b

func testPost(a,b: string): string {.post(app, "/testpost/@a/@b").} =
  "a: " & a & ", b: " & b

test "routing: get/post pragma":
  check testRoutes(HttpGet , @["testget", "test_a", "test_b"] , expectText = "a: test_a, b: test_b")
  check testRoutes(HttpPost, @["testpost", "test_a", "test_b"], expectText = "a: test_a, b: test_b")



func testParse1(a,b: uint): string {.get(app, "/parse1/@a/@b").} =
  $(a + b)

func testParse2(a,b: int64, c: string): string {.get(app, "/parse2/@a/@b/str/@c").} =
  "a*b=" & $(a*b) & ", c=" & c

func testParse3(x: 1 .. 6): string {.get(app, "/parse3/@x").} =
  $x

test "routing: parsing parameters":
  check testRoutes(HttpGet, @["parse1", "2", "3"], expectText = "5")
  check testRouteNone(3, HttpGet, @["parse1", "a", "3"])

  check testRoutes(HttpGet, @["parse2", "2", "3", "str", "test"], expectText = "a*b=6, c=test")

  check testRoutes(HttpGet, @["parse3", "2"], expectText = "2")
  check testRouteNone(5, HttpGet, @["parse3", "0"])
  check testRouteNone(5, HttpGet, @["parse3", "7"])



func testMultiRoutes(s: string): string {.get(app, "/multi/@s"), post(app, "/multi/@s"), get(app, "/multi/foo/@s").} =
  s

test "routing: multiple routes for one proc":
  check testRoutes(HttpGet , @["multi", "test"]       , expectText = "test")
  check testRoutes(HttpPost, @["multi", "test"]       , expectText = "test")
  check testRoutes(HttpGet , @["multi", "foo", "test"], expectText = "test")



func testDefaults(a: string, b = "b", c = "c"): string {.get(app, "/default_ab/@a/@b"), get(app, "/default_ac/@a/@c").} =
    a & b & c

test "routing: default values":
  check testRoutes(HttpGet, @["default_ab", "A", "B"], expectText = "ABc")
  check testRoutes(HttpGet, @["default_ac", "A", "C"], expectText = "AbC")



func testResponse1: Response {.get(app, "/response1").} =
  respText(Http200, "test")

proc testResponse2: Future[Response] {.async, get(app, "/response2").} =
  return respText(Http200, "test")

proc testResponse3: Future[string] {.async, get(app, "/response3").} =
  return "test"

test "routing: response types":
  check testRoutes(HttpGet, @["response1"], expectText = "test")
  check testRoutes(HttpGet, @["response2"], expectText = "test")
  check testRoutes(HttpGet, @["response3"], expectText = "test")



func testBody1(body: Body[string]): string {.get(app, "/body1").} =
  "body: " & body

proc testBody2(a: string, body: Body[int]): string {.get(app, "/body2/@a").} =
  a & $(body+1)

test "routing: body":
  check testRoutes(HttpGet, @["body1"]       , "test", expectText = "body: test")
  check testRoutes(HttpGet, @["body2", "foo"], "2"   , expectText = "foo3"      )
  check testRoutes(HttpGet, @["body2", "ba"] , "4"   , expectText = "ba5"       )



type
  TestEnum = enum teA, teB
  TestObj = object
    case kind: TestEnum
      of teA: a: int
      of teB: b: float
    c: string

proc testJson1(obj: Body[Json[TestObj]]): string {.get(app, "/json").} =
  case obj.kind
    of teA: "a+1=" & $(obj.a + 1) & ", c=" & obj.c
    of teB: "b/2=" & ($(obj.b / 2.0))[0 .. 3] & ", c=" & obj.c

proc testJson2(e: Json[TestEnum]): string {.get(app, "/json2/@e").} =
  result = case e
    of teA: "a"
    of teB: "b"

test "routing: parsing json":
  check testRoutes(HttpGet, @["json"], TestObj(kind: teA, a: 2, c: "x").toJson, expectText = "a+1=3, c=x")
  check testRoutes(HttpGet, @["json2", teA.toJson], expectText = "a")



type
  Op = enum opAdd, opSub
  Calc = object
    op: Op
    left, right: int

func testForm1(calc: Form[Calc]): string {.get(app, "/form1"), post(app, "/form1").} =
  case calc.op
  of opAdd: $(calc.left + calc.right)
  of opSub: $(calc.left - calc.right)

test "routing: form":
  check testRoutes(HttpPost, @["form1"], body     = "op=opAdd&left=2&right=3", expectText = "5")
  check testRoutes(HttpPost, @["form1"], body     = "op=opSub&left=5&right=6", expectText = "-1")
  check testRoutes(HttpGet , @["form1"], queryStr = "op=opAdd&left=2&right=3", expectText = "5")
  check testRoutes(HttpGet , @["form1"], queryStr = "op=opSub&left=5&right=6", expectText = "-1")



type Address = object
  firstname, lastname, street, nr, city: string
  postcode: uint

func parseParam[T: Address](s: string, _: typedesc[T]): T =
  let
    lines = s.split("\n")
    fullname = lines[0].split(" ")
    streetnr = lines[1].split(" ")
    citypostal = lines[2].split(" ")
  Address(
    firstname: fullname[0 ..< ^1].join(" "),
    lastname:  fullname[^1],
    street:    streetnr[0 ..< ^1].join(" "),
    nr:        streetnr[^1],
    city:      citypostal[1 .. ^1].join(" "),
    postcode:  citypostal[0].parseUInt.uint
  )

func testCustomParse(address: Body[Address]): string {.get(app, "/customParse").} =
  $address

test "routing: custom parsing":
  check testRoutes(HttpGet, @["customParse"],
    "Joel Lienhard\nAt the Something 1a\n12345 Somecity",
    expectText = $Address(
      firstname: "Joel",
      lastname: "Lienhard",
      street: "At the Something",
      nr: "1a",
      city: "Somecity",
      postcode: 12345
    )
  )



proc testCookies(cookies: var CookieJar): string {.get(app, "/cookies").} =
  cookies.del("cookieA")
  "ok"

test "routing: cookies":
  check testRoutes(HttpGet, @["cookies"], cookieStr = "cookieA = a; cookieB = b",
    expectHeaders = @[("Set-Cookie", "cookieA=deleted; Expires=Thu, 01 Jan 1970 00:00:00 GMT")],
    expectText = "ok"
  )