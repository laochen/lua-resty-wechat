local modname = "wechat_proxy"
local _M = { _VERSION = '0.0.2' }
_G[modname] = _M

local ngx_re_sub = ngx.re.sub
local ngx_req_set_uri = ngx.req.set_uri
local ngx_req_get_uri_args = ngx.req.get_uri_args
local ngx_req_set_uri_args = ngx.req.set_uri_args

local lua2cache = require("resty.sns.utils.lua2cache")

local accessTokenKey = sns_config.wechat_accessTokenKey or sns_config.wechat_appid

local mt = {
  __call = function(_, location_root)
    local uri = ngx_re_sub(ngx.var.uri, "^/" .. location_root .. "(.*)", "$1", "o")
    ngx_req_set_uri(uri)

    local args = ngx_req_get_uri_args()
    --args["access_token"] = require("resty.wechat.utils.redis"):connect(sns_config.redis).redis:get(accessTokenKey)
    args["access_token"] = lua2cache.getTokenFromCache(accessTokenKey)

    ngx_req_set_uri_args(args)
  end,
}

return setmetatable(_M, mt)
