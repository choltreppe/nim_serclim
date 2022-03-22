# Serclim
Serclim is a server-client webframework for nim, like ocsigen/eliom in OCaml or ur/web or the language opa.<br>
This is the very first version.<br>
At the moment it lacks a lot of features and may still have some bugs.


## Server/Client in one Code

In serclim all your server-side and client-side code can be written in the same files.<br>
You simply need to compile your project to js, to get the client code and to a binary to get the server code.

Every code that is inside a `client:` block gets only compiled into the client-side code.<br>
And code inside `server:` only into the server-side.<br>
Every code that isn't inside any block is compiled to both.

You may aswell declare just a proc or func to be client or server code with a `client` or `server` pragma.

### Example
```nim
import serclim

server:
  import htmlgen

client:
  import std/dom
  import strutils


func add(a,b: int): int =
  a + b

server:

  var app = newServerApp(client_path = "client.js")

  proc addIndex: Response {. get(app, "/add") .} =
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


proc calc(this: FormElement) {. client, exportc .} =
  let res = add(
    ($this.elements[0].value).parse_int,
    ($this.elements[1].value).parse_int
  )
  document.getElementById("result").innerHTML = res.`$`.cstring
```

compile/run:
```
nim c app.nim
nim js -o:client.js app.nim
./app
```

## Server
to make a new server use `func newServerApp*(client_path: string, static_path = "static", port = 8080): ServerApp`<br>
and start the server with `run(app: ServerApp)`

## Routing
you can declare routes to functions with the `route(app, route, method)` pragma<br>
where {...} in the route are parameters of the proc.<br>
The parameters get parsed automaticaly. suported types are strings, all int/uint types and all float types.<br>
If it can't be parsed into the type, the route simply didnt matched (no error). So you could have multiple procs with the exact same route, just different types.<br>
You can also declare multiple routes for one proc.<br>
There are short forms: `get(app, route)` and `post(app, route)`.

The procs/funcs need to have as return type either `Response` or `string` (or a `Future` of them).<br>
If it is a `string` just that text is returned with code 200.<br>
If it is a `Response` it can either be a plain text or html, in which the link to the client code is automaticly inserted.<br>
(take a look at the code in serclim/server/response for more inside)

## Remote calls (ajax)
If you want to call a proc that is only compiled to server from client side you can use the `ajax(app, path)` pragama.<br>
A proc/func with an ajax pragma can be called from client side just as if it was client-side code. Except that the return type is a Future of the original type, if it inst already a Future.<br>
For parameters an return type **all types** are supported.
### Example
if we don't want the add func of the previous example to be compiled to the client, we coul'd modify it like that:
```nim
import serclim

server:
  import htmlgen

client:
  import std/asyncjs
  import std/dom
  import strutils


server:

  var app = newServerApp(client_path = "client.js")

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

  func addUrl(a,b: int): string {. get(app, "/add/{a}/{b}") .} =
    $add(a, b)

  run app


client:

  proc calc(this: FormElement) {.async, exportc.} =
    let res = await add(
      ($this.elements[0].value).parse_int,
      ($this.elements[1].value).parse_int
    )
    document.getElementById("result").innerHTML = res.`$`.cstring
```
