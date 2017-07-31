## This module is a wrapper for vk.com API.
##
## It gives you the ability to call vk.com API methods using synchronous and asynchronous approach.
##
## In addition this module exposes macro ``@`` to ease calling API methods
##
## Initialization
## ====================
##
## .. code-block:: Nim
##    # Synchronous VK API
##    let api = newVkApi()
##    # Asynchronous VK API
##    let asyncApi = newAsyncVkApi()
##    # If you want to provide token instead of login and password, use this:
##    let api = newVkApi(token="your token")
##
## Authorization
## ====================
##
## .. code-block:: Nim
##    api.login("your login", "your password")
##    # This library also supports 2-factor authentication:
##    api.login("your login", "your password", "your 2fa code")
##    # Async example:
##    waitFor asyncApi.login("login", "password")
##
## Synchronous VK API usage
## ====================
##
## .. code-block:: Nim
##    echo api.apiRequest("friends.getOnline")
##    echo api.apiRequest("fave.getPosts", {"count": "1"}.toApi)
##    echo api.apiRequest("wall.post", {"friends_only": "1", "message": "Hello world from nim-lang"}.toApi)
##
##    echo api@friends.getOnline()
##    echo api@fave.getPosts(count=1)
##    api@wall.post(friends_only=1, message="Hello world from nim-lang")
##
## Asynchronous VK API usage
## ====================
##
## .. code-block:: Nim
##    import asyncdispatch
##    echo waitFor asyncApi.apiRequest("wall.get", {"count": "1"}.toApi)
##    echo waitFor asyncApi@wall.get(count=1)

# HTTP client
import httpclient
# JSON parsing
import json
export json
# `join` procedure
import strutils
# Async and multisync features
import asyncdispatch
# `@` macro
import macros
# URL encoding
import cgi
# String tables
import strtabs
export strtabs


const 
  VkUrl* = "https://api.vk.com/method/"  ## Default API url for vk.com API method calls

  ApiVer* = "5.67" ## Default API version

  AuthScope = "all" ## Default authorization scope

  ClientId = "3140623"  ## Client ID (VK iPhone app)

  ClientSecret = "VeWdmVclDCtn6ihuP1nt"  ## VK iPhone app client secret

type
  VkApiBase*[HttpType] = ref object  ## VK API object base
    token*: string  ## VK API token
    version*: string  ## VK API version
    url*: string  ## VK API url
    when HttpType is HttpClient: client: HttpClient
    else: client: AsyncHttpClient
  
  VkApi* = VkApiBase[HttpClient] ## VK API object for doing synchronous requests
  
  AsyncVkApi* = VkApiBase[AsyncHttpClient] ## VK API object for doing asynchronous requests

  VkApiError* = object of Exception  ## VK API Error

proc newVkApi*(token = "", version = ApiVer, url = VkUrl): VkApi =
  ## Initialize ``VkApi`` object.
  ##
  ## - ``token`` - your VK API access token
  ## - ``version`` - VK API version
  ## - ``url`` - VK API url
  new(result)
  result.token = token
  result.url = url
  result.version = version
  result.client = newHttpClient()

proc newAsyncVkApi*(token = "", version = ApiVer, url = VkUrl): AsyncVkApi =
  ## Initialize ``AsyncVkApi`` object.
  ##
  ## - ``token`` - your VK API access token
  ## - ``version`` - VK API version
  ## - ``url`` - VK API url
  new(result)
  result.token = token
  result.url = url
  result.version = version
  result.client = newAsyncHttpClient()

proc encode(params: StringTableRef): string =
  ## Encodes parameters for POST request and returns POST request body
  result = ""
  var parts = newSeq[string]()
  # For every key, value pair
  for key, val in pairs(params):
    # URL-encode key and value
    let
      enck = cgi.encodeUrl(key)
      encv = cgi.encodeUrl(val)
    # Add encoded values to result
    parts.add($enck & "=" & $encv)
  # Join all values by "&" for POST request
  result.add(parts.join("&"))

proc login*(api: VkApi | AsyncVkApi, login, password: string, 
            code = "", scope = AuthScope) {.multisync.} = 
  ## Login in VK using login and password (optionally 2-factor code)
  ##
  ## - ``api`` - VK API object
  ## - ``login`` - VK login
  ## - ``password`` - VK password
  ## - ``code`` - if you have 2-factor auth, you need to provide your 2-factor code
  ## - ``scope`` - authentication scope, default is "all"
  ## Example:
  ##
  ## .. code-block:: Nim
  ##    let api = newVkApi()
  ##    api.login("your login", "your password")
  ##    echo api@users.get()
  # Authorization data
  let data = {
    "client_id": ClientId, 
    "client_secret": ClientSecret, 
    "grant_type": "password", 
    "username": login, 
    "password": password, 
    "scope": scope, 
    "v": ApiVer,
    "2fa-supported": "1"
  }.newStringTable()
  # If user has provided 2factor code, add it to parameters
  if code != "":
    data["code"] = code
  # Send our requests. We don't use postContent since VK can answer 
  # with other HTTP response codes than 200
  let resp = await api.client.post("https://oauth.vk.com/token", 
                                   body=data.encode())
  # Parse answer as JSON. We need this `when` statement because with
  # async http client we need "await" body of the response
  let answer = when resp is AsyncResponse: parseJson(await resp.body)
             else: parseJson(resp.body)
  if "error" in answer:
    # If some error happened
    raise newException(VkApiError, answer["error_description"].str)
  else:
    # Set VK API token
    api.token = answer["access_token"].str

template toApi*(data: untyped): StringTableRef = 
  ## Shortcut for newStringTable to create arguments for apiRequest call
  data.newStringTable()

proc apiRequest*(api: VkApi | AsyncVkApi, name: string, 
                 params = newStringTable()): Future[JsonNode] {.multisync.} =
  ## Main method for  VK API requests.
  ##
  ## - ``api`` - API object (``VkApi`` or ``AsyncVkApi``)
  ## - ``name`` - namespace and method separated with dot (https://vk.com/dev/methods)
  ## - ``params`` - StringTable with parameters
  ## - ``return`` - returns response as JsonNode object
  ## Examples:
  ##
  ## .. code-block:: Nim
  ##    echo api.apiRequest("friends.getOnline")
  ##    echo api.apiRequest("fave.getPosts", {"count": "1"}.toApi)
  ##    echo api.apiRequest("wall.post", {"friends_only": "1", "message": "Hello world from nim-lang"}.toApi)
  params["v"] = api.version
  params["access_token"] = api.token
  # Send request to API
  let body = await api.client.postContent(api.url & name, body=params.encode())
  # Parse response as JSON
  let data = body.parseJson()
  # If some error happened
  if "error" in data:
    # Error object
    let error = data["error"]
    # Error code
    let code = error["error_code"].num
    case code
    of 3:
      raise newException(VkApiError, "Unknown VK API method")
    of 5:
      raise newException(VkApiError, "Authorization failed: invalid access token")
    of 6:
      # TODO: RPS limiter
      raise newException(VkApiError, "Too many requests per second")
    of 14:
      # TODO: Captcha handler
      raise newException(VkApiError, "Captcha is required")
    of 17:
      raise newException(VkApiError, "Need validation code")
    else:
      raise newException(VkApiError, "Error code $1: $2 " % [$code, 
                         error["error_msg"].str])
  result = data.getOrDefault("response")
  if result.isNil(): result = data

macro `@`*(api: VkApi | AsyncVkApi, body: untyped): untyped =
  ## `@` macro gives you the ability to make API calls in more convenient manner
  ##
  ## Left argument is ``VkApi`` or ``AsyncVkApi`` object. 
  ## Right one is a namespace and method name separated by dot.
  ##
  ## And finally in parentheses you can specify any number of named arguments.
  ##
  ##
  ## This macro is transformed into ``apiRequest`` call with parameters 
  ##
  ## Example:
  ##
  ## .. code-block:: Nim
  ##    echo api@friends.getOnline()
  ##    echo api@fave.getPosts(count=1, offset=50)
  assert body.kind == nnkCall
  # Let's create a table, which will have API parameters
  var table = newNimNode(nnkTableConstr)
  # Full API method name
  let name = body[0].toStrLit
  # Check all arguments inside of call
  for arg in body.children:
    # If it's a equality expression "abcd=something"
    if arg.kind == nnkExprEqExpr:
      # Convert key to string, and call $ for value to convert it to string
      table.add(newColonExpr(arg[0].toStrLit, newCall("$", arg[1])))
  # Finally create a statement to call API
  result = quote do:
    `api`.apiRequest(`name`, `table`.toApi)
