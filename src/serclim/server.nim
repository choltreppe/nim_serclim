import std/[options, tables, os, compilesettings]
import std/[httpcore, asynchttpserver, asyncdispatch]
import std/htmlgen

include serclim/server/routing
import serclim/server/response

export strutils, options, asyncdispatch, httpcore
export response


# ignore client. keep server
macro client*(_: untyped): untyped = discard
macro server*(body: untyped): untyped = body


const clientFile {.strdefine.} = "client.js"
const clientCode = block:
  if clientFile == "": ""
  else:
    let clientPath = querySetting(projectPath) / clientFile
    let compileDefines = querySetting(commandLine).split(" ").filterIt(it.startsWith("-d:")).join(" ")
    discard staticExec(fmt"nim js -o:{clientPath} {compileDefines} {querySetting(projectFull)}")
    let code = staticRead(clientPath)
    let rmCmd =
      if defined(windows): "del"
      else:                "rm"
    discard staticExec(fmt"{rmCmd} {clientPath}")
    code


type
  ServerApp* = object
    port: int
    headers: tuple[text,html: RespHeaders]
    handlers*: seq[proc(
      meth: HttpMethod,
      pathSeq: seq[string],
      body: string,
      queryStr: string,
      cookieStr: string):
      Future[Option[Response]] {.async, closure.}
    ]

let defaultHeaders: tuple[text,html: RespHeaders] = (
  @[("Content-type", "text/plain; charset=utf-8")],
  @[("Content-type", "text/html; charset=utf-8")]
)


func newServerApp*(port = 8080, headers = defaultHeaders): ServerApp =
  ServerApp(port: port, headers: headers)


proc run*(app: ServerApp) =
  proc serve {.async.} =
    var server = newAsyncHttpServer()
    
    proc cb(req: Request) {.async, gcsafe.} =
      try:

        let relPath = req.url.path[1 .. ^1]
        
        # serve client js script
        if relPath == clientFile:
          await req.respond(Http200, clientCode)
          return

        let pathSeq = relPath.split('/')

        let headers = req.headers.table
        let cookieStr =
          if headers.contains("Cookies"):
            headers["Cookies"].join(";")
          elif headers.contains("cookies"):
            headers["cookies"].join(";")
          else: ""

        for i in 0 ..< app.handlers.len:
          if Some(@resp) ?= await app.handlers[i](req.reqMethod, pathSeq, req.body, req.url.query, cookieStr):
            await req.respond(
              resp.code,
              case resp.kind:
                of respOther: resp.text
                of respHtml:
                  html(
                    head(resp.html.head),
                    body(script(src = ("/" & clientFile)), resp.html.body)
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

  setCurrentDir(getAppDir())
  waitFor serve()