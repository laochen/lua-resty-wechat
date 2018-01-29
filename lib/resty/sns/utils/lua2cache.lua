local modname = "sns_lua2cache"
local _M = { _VERSION = '0.0.1' }
_G[modname] = _M

local function get_token_from_cache(key)
    local resty_lock = require "resty.lock"
    local cache = ngx.shared.my_cache

    -- step 1:
    local val, err = cache:get(key)
    if val then
        return val
    end

    if err then
        ngx.log(ngx.ERR, "failed to get key from shm: "..err))
        return nil
    end

    -- cache miss!
    -- step 2:
    local lock, err = resty_lock:new("my_locks")
    if not lock then
        ngx.log(ngx.ERR, "failed to create lock: "..err))
        return nil
    end

    local elapsed, err = lock:lock(key)
    if not elapsed then
        ngx.log(ngx.ERR, "failed to acquire the lock: "..err))
        return nil
    end

    -- lock successfully acquired!

    -- step 3:
    -- someone might have already put the value into the cache
    -- so we check it here again:
    val, err = cache:get(key)
    if val then
        local ok, err = lock:unlock()
        if not ok then
            ngx.log(ngx.ERR, "failed to unlock:  "..err))
            return nil
        end

        return val
    end

    --- step 4:
    local val = require("resty.sns.utils.redis"):connect(wechat_config.redis).redis:get(key)
    if not val then
        local ok, err = lock:unlock()
        if not ok then
            ngx.log(ngx.ERR, "failed to unlock:  "..err))
            return nil
        end

        -- FIXME: we should handle the backend miss more carefully
        -- here, like inserting a stub value into the cache.
        ngx.log(ngx.ERR, "redis no value found"))
        return nil
    end

    --- step 5:
    ---- get ttl
    local ttl = tonumber(require("resty.wechat.utils.redis"):connect(sns_config.redis).redis:ttl(key) or 0)
    if ttl <= 0 then
        local ok, err = lock:unlock()
        if not ok then
            ngx.log(ngx.ERR, "failed to unlock:  "..err))
            return nil
        end

        -- FIXME: we should handle the backend miss more carefully
        -- here, like inserting a stub value into the cache.
        ngx.log(ngx.ERR, "redis key ttl is 0"))
        return nil
    end

    -- update the shm cache with the newly fetched value
    local ok, err = cache:set(key, val, ttl+math.random(100))
    if not ok then
        local ok, err = lock:unlock()
        if not ok then
            ngx.log(ngx.ERR, "failed to unlock:  "..err))
            return nil
        end
        ngx.log(ngx.ERR, "failed to update shm cache: "..err))
        return nil
    end

    local ok, err = lock:unlock()
    if not ok then
            ngx.log(ngx.ERR, "failed to unlock:  "..err))
            return nil
    end

    return val
end


function _M.getTokenFromCache(s)
  local result = get_token_from_cache(s)
  return result
end

return _M
