local modname = "weibo_oauth"
local _M = { _VERSION = '0.0.1' }
_G[modname] = _M

local cjson = require("cjson")

local ngx_log = ngx.log
local ngx_exit = ngx.exit

--------------------------------------------------private methods
local access_token_addr = "https://api.weibo.com/oauth2/access_token"

local function oauth_access_token(code)
  local param = {
    method = "GET",
    query = {
      grant_type = "authorization_code",
      client_id = sns_config.weibo_appid,
      client_secret = sns_config.weibo_appsecret,
      code = code,
      redirect_uri = sns_config.weibo_redirect_uri
    },
    ssl_verify = false,
    headers = { ["Content-Type"] = "application/x-www-form-urlencoded" },
  }

  local res, err = require("resty.sns.utils.http").new():request_uri(access_token_addr, param)
  if not res or err or tostring(res.status) ~= "200" then
    return nil, err or tostring(res.status)
  end

  local resbody = cjson.decode(res.body)
  if not resbody.access_token then
    return nil, res.body
  end

  return resbody
end

local userinfo_addr = "https://api.weibo.com/2/users/show.json"

local function oauth_userinfo(access_token, uid)
  local param = {
    method = "GET",
    query = {
      access_token = access_token,
      uid = uid,
    },
    ssl_verify = false,
    headers = { ["Content-Type"] = "application/x-www-form-urlencoded" },
  }

  local res, err = require("resty.sns.utils.http").new():request_uri(userinfo_addr, param)
  if not res or err or tostring(res.status) ~= "200" then
    return nil, err or tostring(res.status)
  end

  local resbody = cjson.decode(res.body)
  if not resbody.uid then
    return nil, res.body
  end

  return resbody
end

local function request_oauth_infomation(code)
  local baseinfo, err = oauth_access_token(code)
  if err then return nil, nil, "failed to get oauth access token: " .. err end

  local userinfo, err = oauth_userinfo(baseinfo.access_token, baseinfo.uid)
  if err then return nil, nil, "failed to get oauth userinfo: " .. err end

  return { uid = baseinfo.uid }, userinfo
end


--------------------------------------------------public methods
----------------增加code授权获取用户信息接口-----------------------
function _M.oauth_by_code(code)
  if not code then -- unauthorized
    ngx_log(ngx.ERR, "code is empty")
    return ngx_exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
  end

  return request_oauth_infomation(tostring(code))
end

return _M
