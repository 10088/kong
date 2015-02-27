local stringy = require "stringy"
local constants = require "kong.constants"

local _M = {}

local function get_backend_url(api)
  local result = api.target_url

  -- Checking if the target url ends with a final slash
  local len = string.len(result)
  if string.sub(result, len, len) == "/" then
    -- Remove one slash to avoid having a double slash
    -- Because ngx.var.uri always starts with a slash
    result = string.sub(result, 0, len - 1)
  end

  return result
end

local function skip_authentication(headers)
  -- Skip upload request that expect a 100 Continue response
  return headers["expect"] and _M.starts_with(headers["expect"], "100")
end

local function load_api(host)
  local apis, err = dao.apis:find_by_keys({public_dns = host})
  if err then
    ngx.log(ngx.ERR, err.message)
    utils.show_error(500)
  elseif not apis or #apis == 0 then
    utils.not_found("API not found")
  end
  return apis[1]
end

function _M.execute(conf)
  -- Retrieving the API from the Host that has been requested
  local host = stringy.strip(stringy.split(ngx.var.http_host, ":")[1])

  local cache_key = utils.cache_api_key(host)
  local api = utils.cache_get(cache_key)
  if not api then
    api = load_api(host)
    local ok, err = utils.cache_set(cache_key, api, 5)
    if not ok then
      ngx.log(ngx.ERR, err)
    end
  end

  -- Setting the backend URL for the proxy_pass directive
  ngx.var.backend_url = get_backend_url(api) .. ngx.var.request_uri

  -- There are some requests whose authentication needs to be skipped
  if skip_authentication(ngx.req.get_headers()) then
    return -- Returning and keeping the Lua code running to the next handler
  end

  -- Saving these properties for the other handlers, especially the log handler
  ngx.ctx.api = api
end

return _M
