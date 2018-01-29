local modname = "wechat_oauth"
local _M = { _VERSION = '0.0.2' }
_G[modname] = _M

local urlcodec = require("resty.sns.utils.urlcodec")
local base62 = require("resty.sns.utils.base62")
local cjson = require("cjson")
local aescodec = require("resty.sns.utils.aes").new(sns_config.wechat_cookie_aes_key or "vFrItmxI9ct8JbAg")
local cookie = require("resty.sns.utils.cookie")
local base_oauth_key = sns_config.wechat_base_oauth_key or "__rywy_base"
local userinfo_oauth_key = sns_config.wechat_userinfo_oauth_key or "__rywy_userinfo"

local ngx_log = ngx.log
local ngx_exit = ngx.exit

--------------------------------------------------private methods

local authorize_addr = "https://open.weixin.qq.com/connect/oauth2/authorize?appid=" .. sns_config.wechat_appid .. "&redirect_uri="
local response_type_and_scope = "&response_type=code&scope="
local state = "&state="
local hash = "#wechat_redirect?"

local function build_oauth_redirect_addr(redirect_uri, scope, target)
  return authorize_addr .. urlcodec.encodeURI(redirect_uri) .. response_type_and_scope .. scope .. state .. base62:encode(target) .. hash
end

local access_token_addr = "https://api.weixin.qq.com/sns/oauth2/access_token"

local function oauth_access_token(code)
  local param = {
    method = "GET",
    query = {
      grant_type = "authorization_code",
      appid = sns_config.wechat_appid,
      secret = sns_config.wechat_appsecret,
      code = code,
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

local userinfo_addr = "https://api.weixin.qq.com/sns/userinfo"

local function oauth_userinfo(access_token, openid)
  local param = {
    method = "GET",
    query = {
      access_token = access_token,
      openid = openid,
    },
    ssl_verify = false,
    headers = { ["Content-Type"] = "application/x-www-form-urlencoded" },
  }

  local res, err = require("resty.sns.utils.http").new():request_uri(userinfo_addr, param)
  if not res or err or tostring(res.status) ~= "200" then
    return nil, err or tostring(res.status)
  end

  local resbody = cjson.decode(res.body)
  if not resbody.openid then
    return nil, res.body
  end

  return resbody
end

local function request_oauth_infomation(code)
  local baseinfo, err = oauth_access_token(code)
  if err then return nil, nil, "failed to get oauth access token: " .. err end

  if baseinfo.scope ~= "snsapi_userinfo" then
    return { openid = baseinfo.openid }
  end

  local userinfo, err = oauth_userinfo(baseinfo.access_token, baseinfo.openid)
  if err then return nil, nil, "failed to get oauth userinfo: " .. err end

  return { openid = baseinfo.openid }, userinfo
end

local function process_share_from_param(target)
  local from_param = ngx.var.arg_from
  if not from_param then return target end
  return target .. (string.match(target, "?") and "&" or "?") .. "from=" .. from_param
end

--------------------------------------------------public methods

function _M.base_oauth(redirect_uri, goto_param_name)
  local goto_param = ngx.var["arg_" .. (goto_param_name or "goto")]
  if not goto_param then return ngx_exit(ngx.HTTP_BAD_REQUEST) end
  local target = process_share_from_param(urlcodec.decodeURI(goto_param))

  if cookie.get(base_oauth_key) then
    return ngx.redirect(target, ngx.HTTP_MOVED_TEMPORARILY)
  end
  return ngx.redirect(build_oauth_redirect_addr(redirect_uri, "snsapi_base", target), ngx.HTTP_MOVED_TEMPORARILY)
end

function _M.userinfo_oauth(redirect_uri, goto_param_name)
  local goto_param = ngx.var["arg_" .. (goto_param_name or "goto")]
  if not goto_param then return ngx_exit(ngx.HTTP_BAD_REQUEST) end
  local target = process_share_from_param(urlcodec.decodeURI(goto_param))

  if cookie.get(userinfo_oauth_key) then
    return ngx.redirect(target, ngx.HTTP_MOVED_TEMPORARILY)
  end
  return ngx.redirect(build_oauth_redirect_addr(redirect_uri, "snsapi_userinfo", target), ngx.HTTP_MOVED_TEMPORARILY)
end

function _M.redirect()
  local state = base62:decode(tostring(ngx.var.arg_state))
  if not ngx.var.arg_code then -- unauthorized
    return ngx.redirect(state, ngx.HTTP_MOVED_TEMPORARILY)
  end

  local code = tostring(ngx.var.arg_code)
  local baseinfo, userinfo, err = request_oauth_infomation(code)
  if err then
    ngx_log(ngx.ERR, err)
    return ngx_exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
  end

  local encrypted_baseinfo = ngx.encode_base64(aescodec:encrypt(cjson.encode(baseinfo)))
  cookie.set({
    key = base_oauth_key,
    value = encrypted_baseinfo,
    expires = ngx.cookie_time(ngx.now() + 7200),
    domain = sns_config.wechat_cookie_domain,
    path = sns_config.wechat_cookie_path,
  })

  if userinfo then
    local encrypted_userinfo = ngx.encode_base64(aescodec:encrypt(cjson.encode(userinfo)))
    cookie.set({
      key = userinfo_oauth_key,
      value = encrypted_userinfo,
      expires = ngx.cookie_time(ngx.now() + 7200),
      domain = sns_config.wechat_cookie_domain,
      path = sns_config.wechat_cookie_path,
    })
  end

  ngx.log(ngx.ERR, cjson.encode(ngx.header.Set_Cookie))

  return ngx.redirect(state, ngx.HTTP_MOVED_TEMPORARILY)
end

----------------增加code授权获取用户信息接口-----------------------
function _M.oauth_by_code(code)
  if not code then -- unauthorized
    ngx_log(ngx.ERR, "code is empty")
    return ngx_exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
  end

  return request_oauth_infomation(tostring(code))
end

return _M
