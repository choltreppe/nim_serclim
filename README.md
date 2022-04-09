# Serclim
Serclim is a server-client webframework for nim, like ocsigen/eliom in OCaml or ur/web or the language opa.<br>
This is the very first version.<br>
At the moment it lacks a lot of features and may still have some bugs.


## Example

Heres a short example illustrating some of the features, explained in detail below.
```nim
import serclim

server:
  import htmlgen

client:
  import std/asyncjs
  import std/dom
  import strutils


server:

  var app = newServerApp(clientPath = "client.js")

  func add(a,b: int): int {. ajax(app, "/ajax/add") .} =
    a + b

  proc addGui: Response {. get(app, "/add") .} =
    respOk(
      link(rel="stylesheet", `type`="text/css", href="/static/style.css"),
      form(
        onsubmit="event.preventDefault(); calc(this)",
        input(type="text", name="a"),
        "+",
        input(type="text", name="b"),
        button("calc"),
        p(id="result")
      )
    )

  run app


client:

  proc calc(this: FormElement) {.async, exportc.} =
    let res = await add(
      ($this.elements[0].value).parseInt,
      ($this.elements[1].value).parseInt
    )
    document.getElementById("result").innerHTML = res.`$`.cstring
```



## Server/Client in one Code

In serclim all your server-side and client-side code can be written in the same files.<br>
You simply need to compile your project to js, to get the client code and to a binary to get the server code.

Every code that is inside a `client:` block gets only compiled into the client-side code.<br>
And code inside `server:` only into the server-side.<br>
Every code that isn't inside any block is compiled to both.

You may aswell declare just a proc or func to be client or server code with a `client` or `server` pragma.

```nim
import serclim

server:
  # server-side code

client:
  # client-side code

# shared code

proc example() {.server.} = discard  # also server-side
```


## Server
to make a new server use `func newServerApp*(clientPath: string, staticPath = "static", port = 8080, headers = defaultHeaders): ServerApp`<br>
Where `clientPath` is the path where the compiled client-side code is located.<br>
And `staticPath` the path where static content is located, that schould get served automatically.<br>
And `headers` is a `tuple[text, html: seq[(string, string)]]`. It defines default headers for html and text responses. ()
and start the server with `run(app: ServerApp)`<br>
inbetween creating and starting the server you can define different routes for functions and define functions as remote callable.

## Routing
you can declare routes to procs/funcs with the `route(app, route, method)` pragma<br>
where `app` is the server-app, `method` is the http-method (directly exported from `std/httpcore`)<br>
and `route` is a path with interpolated parameters that the function should be associated with.<br>
The parameters in the route are between `{` .. `}`.<br>
```nim
server:
  var app = newServerApp(clientPath = "client.js")

  func repeateTwice(text: string): string {.route(app, "/twice/{text}", HttpGet)}

  app.run
```

For `HttpGet` and `HttpPost` you can use `get(app, route)` and `post(app, route)` short forms
```nim
func repeateTwice(text: string): string {.get(app, "/twice/{text}"), post(app, "/twice/{text}").} =
  text & text
```

You can also use default values for parameters, so you dont have to capture them in the route.
```nim
func chainABC(a: string, b = "b", c = "c"): string {.get("/chain/ab/{a}/{b}"), get("/chain/ac/{a}/{c}").} =
  a & b & c
```

As you can see in the example, you can define as many routes for one proc/func as you like.

Out of the boy supported types are `string`, `int`, `int8`, `int16`, `int32`, `int64`, `uint`, `uint8`, `uint16`, `uint32`, `uint64`, `float`, `float32`, `float64`, `enum`, `range`<br>
They will get parsed automatically. And if they cant be parsed, the route does not match and the server will try the other routes.
```nim
func add(a,b: int16): string {.get(app, "/add/{a}/{b}").} =
  a + b
```
```nim
func add(month: 1 .. 12): string {.get(app, "/something_with_month/{month}").} =
  # do something
```
But if you need some other type you can define a `parseParam` proc for it, to define a custom parser.
```nim
type Address = object
  firstname, lastname, street, nr, city: string
  postcode: uint

func parseParam[T: Address](s: string, _: typedesc[T]): T =
  let lines = s.split("\n")
  let fullname = lines[0].split(" ")
  let streetnr = lines[1].split(" ")
  let citypostal = lines[2].split(" ")
  Address(
    firstname: fullname[0 ..< ^1].join(" "),
    lastname:  fullname[^1],
    street:    streetnr[0 ..< ^1].join(" "),
    nr:        streetnr[^1],
    city:      citypostal[1 .. ^1].join(" "),
    postcode:  citypostal[0].parseUInt.uint
  )
```
If you want to use another type, you can use the `Json[T]` type, which is just a compiletime info for the routing pragma that the parameter is json-formated.<br>
The type is defined as `type Json[T] = T` so its just a value of type `T`.<br>
```nim
type
  UserKind = enum ukNormal, ukAdmin
  User = object
    kind: Userkind
    name: string

var users: seg[User]

proc addUser(user: Json[User]): string {.post(app, "/user/add/{user}").}
  users.add(user)
  ""
```

## auto injected parameters

### Body
If you want to use the body of the request, you can use the `Body[T]` type, which is just a compiletime info like the Json type.
Parameters with that type get the body content parsed into `T` foloowing the same rules as route parameters.
```nim
func succ(x: Body[int]): string {.get(app, "/succ").} =
  x + 1
```
```nim
type
  UserKind = enum ukNormal, ukAdmin
  User = object
    kind: Userkind
    name: string

var users: seg[User]

proc addUser(user: Body[Json[User]]): string {.post(app, "/user/add").}
  users.add(user)
  ""
```

### CookieJar

If you want to handle cookies you can use a `CookieJar` parameter.<br>
Or `var CookieJar` if you want to edit them.<br>
```nim
import serclim/server/cookies

proc cookieStuff(cookies: var CookieJar): string {.get(app, "/cookies").} =
  cookieJar.del("cookieA")
  cookieJar["cookieB"] = "foo"
  cookieJar.add("withAttr", "ba",
    expires = dateTime(1999, mJun, 10, 13, 37, 42, 0, utc()),
    path = "/bla",
    domain = "example.org",
    secure = true,
    httpOnly = true
  )
  ""
```

### Response

Posible return types are: `string`, `Response`, `Future[string]` or `Future[Response]`.<br>
Ẁhen a `string` is returned, the content is returned as text with code 200 ok.<br>
Whith the `Response` type you can either return a text or html kind.<br>
In the case of html its split into `head` and `body`, the reason for that is so the client script can be easily included automatically.

There are multiple procs for creating responses.<br>
Take a look at `serclim/server/response.nim`


## Remote calls (ajax)
If you want to call a proc that is only compiled to server from client side you can use the `ajax(app, path)` pragama.<br>
A proc/func with an ajax pragma can be called from client side just as if it was client-side code. Except that the return type is a Future of the original type, if it inst already a Future.<br>
For parameters an return type **all types** are supported.
```nim
import serclim

server:
  import htmlgen

client:
  import std/asyncjs
  import std/dom
  import strutils


server:

  var app = newServerApp(clientPath = "client.js")

  func add(a,b: int): int {. ajax(app, "/ajax/add") .} =
    a + b

  proc addGui: Response {. get(app, "/add") .} =
    respOk(
      link(rel="stylesheet", `type`="text/css", href="/static/style.css"),
      form(
        onsubmit="event.preventDefault(); calc(this)",
        input(type="text", name="a"),
        "+",
        input(type="text", name="b"),
        button("calc"),
        p(id="result")
      )
    )

  run app


client:

  proc calc(this: FormElement) {.async, exportc.} =
    let res = await add(
      ($this.elements[0].value).parseInt,
      ($this.elements[1].value).parseInt
    )
    document.getElementById("result").innerHTML = res.`$`.cstring
```
