import std/options
import std/tables
import std/marshal
import std/httpcore
import std/asynchttpserver
import std/asyncdispatch
import std/htmlgen

include server/routing
import server/response

export strutils, options, marshal, asyncdispatch, httpcore
export response


# ignore client. keep server
macro client*(_: untyped): untyped = discard
macro server*(body: untyped): untyped = body


type
  ServerApp* = object
    staticPath: string
    clientPath: string
    port: int
    handlers*: seq[proc(meth: HttpMethod, path: seq[string], body: string, cookieStr: string): Future[Option[Response]] {.async, closure.}]
    headers: tuple[text,html: RespHeaders]

let defaultHeaders: tuple[text,html: RespHeaders] = (
  @[("Content-type", "text/plain; charset=utf-8")],
  @[("Content-type", "text/html; charset=utf-8")]
)


func newServerApp*(clientPath: string, staticPath = "static", port = 8080, headers = defaultHeaders): ServerApp =
  ServerApp(staticPath: staticPath, clientPath: clientPath, port: port, headers: headers)


proc run*(app: ServerApp) =
  proc loop {.async.} =
    var server = newAsyncHttpServer()
    
    proc cb(req: Request) {.async, gcsafe.} =
      
      try:
        let path_rel = req.url.path[1 .. ^1]
        
        if path_rel == app.clientPath:
          await req.respond(Http200, readFile(app.clientPath))
          return

        if path_rel.startsWith(app.staticPath):
          try:
            let content = readFile(path_rel)
            await req.respond(Http200, content)
          except:
            await req.respond(Http404, "Page not found")
          return


        let path = path_rel.split('/')

        let headers = req.headers.table
        let cookieStr =
          if headers.contains("Cookies"):
            headers["Cookies"].join(";")
          elif headers.contains("cookies"):
            headers["cookies"].join(";")
          else: ""

        for i in 0 ..< app.handlers.len:
          if Some(@resp) ?= await app.handlers[i](req.reqMethod, path, req.body, cookieStr):
            await req.respond(
              resp.code,
              case resp.kind:
                of respOther: resp.text
                of respHtml:
                  html(
                    head(resp.html.head),
                    body(script(src = ("/" & app.clientPath)), resp.html.body)
                  )
              ,
              newHttpHeaders(
                (
                  case resp.kind:
                    of respOther: app.headers.text
                    of respHtml: app.headers.html
                )
                .add(resp.headers)
              )
            )
            return

        await req.respond(Http404, "Page not found")

      except Exception as e:
        await req.respond(Http404, "Server Error")
        echo "Error: " & e.msg


    server.listen(Port(app.port))
    while true:
      if server.shouldAcceptRequest():
        await server.acceptRequest(cb)
      else:
        # too many concurrent connections, `maxFDs` exceeded
        # wait 500ms for FDs to be closed
        await sleepAsync(500)


  waitFor loop()

