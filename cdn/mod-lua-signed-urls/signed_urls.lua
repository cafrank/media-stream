--[[
signed_urls.lua: mod_lua access checker for signed file URLs (#17)

Verifies the URLs media-service signs (GcsSignUrl, the Cloud CDN signed-URL format):

    <BASE_URL><path>?[params&]Expires=<unix seconds>&KeyName=<name>&Signature=<base64url(HMAC-SHA1(key, S))>

S is everything before "&Signature=", including BASE_URL. The signature covers the path and every
parameter before it (so download=1 can't be added or removed), and must be the last parameter.

Pure Lua 5.1: CentOS 7's Lua has no bit library, so the bit operations are done with 4-bit lookup
tables. A verified signature is cached per httpd process until it expires, so the range requests
of one video pay for the HMAC once.

Apache config (see README.md):
    LuaHookAccessChecker /etc/httpd/signed-urls/signed_urls.lua check_signed_url       -- enforce: 403
    LuaHookAccessChecker /etc/httpd/signed-urls/signed_urls.lua check_signed_url_log   -- log only
Keys: KEYS_FILE, one "<KeyName> <base64url key>" per line, reread every KEY_RELOAD_SECONDS.
]]

local BASE_URL = "https://www.my12inch.com"       -- scheme and host that media-service signs
local KEYS_FILE = "/etc/httpd/signed-urls/keys"
local KEY_RELOAD_SECONDS = 60
local CACHE_MAX = 20000                           -- verified signatures kept per process

local floor, char, byte, concat, rep = math.floor, string.char, string.byte, table.concat, string.rep
local MOD32 = 4294967296

-- ---------------------------------------------------------------------------------------------
-- 32-bit operations on numbers in [0, 2^32), with 4-bit lookup tables
local XOR4, AND4, OR4 = {}, {}, {}
for a = 0, 15 do
    for b = 0, 15 do
        local x, y, o, bitv, aa, bb = 0, 0, 0, 1, a, b
        for _ = 1, 4 do
            local ab, bbit = aa % 2, bb % 2
            if ab ~= bbit then x = x + bitv end
            if ab == 1 and bbit == 1 then y = y + bitv end
            if ab == 1 or bbit == 1 then o = o + bitv end
            aa, bb, bitv = (aa - ab) / 2, (bb - bbit) / 2, bitv * 2
        end
        XOR4[a * 16 + b], AND4[a * 16 + b], OR4[a * 16 + b] = x, y, o
    end
end

local function op32(t, a, b)
    local r, m = 0, 1
    for _ = 1, 8 do
        local na, nb = a % 16, b % 16
        r = r + t[na * 16 + nb] * m
        a, b, m = (a - na) / 16, (b - nb) / 16, m * 16
    end
    return r
end
local function bxor(a, b) return op32(XOR4, a, b) end
local function band(a, b) return op32(AND4, a, b) end
local function bor(a, b) return op32(OR4, a, b) end
local function rotl(a, n)   -- stays below 2^53, so doubles are exact
    local split = 2 ^ (32 - n)
    return (a % split) * 2 ^ n + floor(a / split)
end

-- ---------------------------------------------------------------------------------------------
-- SHA-1 (FIPS 180-4) and HMAC-SHA1 (RFC 2104), returning raw 20-byte strings
local function be32(n)
    return char(floor(n / 16777216) % 256, floor(n / 65536) % 256, floor(n / 256) % 256, n % 256)
end

local function sha1(msg)
    local h0, h1, h2, h3, h4 = 0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0
    local bits = #msg * 8
    msg = msg .. "\128" .. rep("\0", (55 - #msg) % 64) .. be32(floor(bits / MOD32)) .. be32(bits % MOD32)
    local w = {}
    for i = 1, #msg, 64 do
        for j = 0, 15 do
            local a, b, c, d = byte(msg, i + j * 4, i + j * 4 + 3)
            w[j] = ((a * 256 + b) * 256 + c) * 256 + d
        end
        for j = 16, 79 do
            w[j] = rotl(bxor(bxor(w[j - 3], w[j - 8]), bxor(w[j - 14], w[j - 16])), 1)
        end
        local a, b, c, d, e = h0, h1, h2, h3, h4
        for j = 0, 79 do
            local f, k
            if j < 20 then
                f, k = bxor(d, band(b, bxor(c, d))), 0x5A827999          -- (b and c) or (not b and d)
            elseif j < 40 then
                f, k = bxor(bxor(b, c), d), 0x6ED9EBA1
            elseif j < 60 then
                f, k = bor(band(b, c), band(d, bor(b, c))), 0x8F1BBCDC    -- majority
            else
                f, k = bxor(bxor(b, c), d), 0xCA62C1D6
            end
            a, b, c, d, e = (rotl(a, 5) + f + e + k + w[j]) % MOD32, a, rotl(b, 30), c, d
        end
        h0, h1, h2, h3, h4 = (h0 + a) % MOD32, (h1 + b) % MOD32, (h2 + c) % MOD32, (h3 + d) % MOD32, (h4 + e) % MOD32
    end
    return be32(h0) .. be32(h1) .. be32(h2) .. be32(h3) .. be32(h4)
end

local function hmac_sha1(key, msg)
    if #key > 64 then key = sha1(key) end
    key = key .. rep("\0", 64 - #key)
    local ipad, opad = {}, {}
    for i = 1, 64 do
        local k = byte(key, i)
        ipad[i], opad[i] = char(bxor(k, 0x36)), char(bxor(k, 0x5C))
    end
    return sha1(concat(opad) .. sha1(concat(ipad) .. msg))
end

-- ---------------------------------------------------------------------------------------------
-- base64url (RFC 4648 §5), encoded with "=" padding as java.util.Base64.getUrlEncoder() does
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
local B64_INDEX = {}
for i = 1, 64 do B64_INDEX[B64:sub(i, i)] = i - 1 end

local function b64url_encode(s)
    local out = {}
    for i = 1, #s, 3 do
        local a, b, c = byte(s, i, i + 2)
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        local c1, c2, c3, c4 = floor(n / 262144) % 64, floor(n / 4096) % 64, floor(n / 64) % 64, n % 64
        out[#out + 1] = B64:sub(c1 + 1, c1 + 1) .. B64:sub(c2 + 1, c2 + 1)
            .. (b and B64:sub(c3 + 1, c3 + 1) or "=") .. (c and B64:sub(c4 + 1, c4 + 1) or "=")
    end
    return concat(out)
end

local function b64url_decode(s)
    s = s:gsub("=+$", "")
    local out, n, bits = {}, 0, 0
    for i = 1, #s do
        local v = B64_INDEX[s:sub(i, i)]
        if not v then return nil end
        n, bits = n * 64 + v, bits + 6
        if bits >= 8 then
            bits = bits - 8
            local octet = floor(n / 2 ^ bits)
            out[#out + 1] = char(octet)
            n = n - octet * 2 ^ bits
        end
    end
    return concat(out)
end

-- Compares every byte, so the time taken doesn't depend on where a forged signature differs
local function equal_ct(a, b)
    if #a ~= #b then return false end
    local diff = 0
    for i = 1, #a do
        if byte(a, i) ~= byte(b, i) then diff = diff + 1 end
    end
    return diff == 0
end

-- ---------------------------------------------------------------------------------------------
-- Keys and the per-process cache
local keys, keys_loaded_at, keys_error = {}, nil, nil

local function load_keys(now)
    if keys_loaded_at and now - keys_loaded_at < KEY_RELOAD_SECONDS then return end
    keys_loaded_at = now
    local f, err = io.open(KEYS_FILE, "r")
    if not f then
        keys_error = "cannot read " .. KEYS_FILE .. ": " .. tostring(err)   -- keep the last good keys
        return
    end
    local loaded = {}
    for line in f:lines() do
        local name, value = line:match("^%s*([%w_.-]+)%s+([%w_=-]+)%s*$")
        if name then
            local key = b64url_decode(value)
            if key and #key > 0 then loaded[name] = key end
        end
    end
    f:close()
    keys, keys_error = loaded, nil
end

local verified, verified_count = {}, 0

-- Keyed by the whole signed URL, not the signature alone: a cached signature must not unlock another path
local function remember(url, expires)
    if verified_count >= CACHE_MAX then verified, verified_count = {}, 0 end
    verified[url] = expires
    verified_count = verified_count + 1
end

-- ---------------------------------------------------------------------------------------------
-- verify(path, query, now): true, or false plus a reason. path is the raw request path, query the
-- raw query string (without "?").
local function verify(path, query, now)
    if not query or query == "" then return false, "unsigned" end
    local signed_part, sig = query:match("^(.*)&Signature=([%w_%%=-]+)$")
    if not signed_part then return false, "no Signature (or not the last parameter)" end
    sig = sig:gsub("%%3[Dd]", "=")

    local params = "&" .. signed_part
    local expires = tonumber(params:match("&Expires=(%d+)"))
    local key_name = params:match("&KeyName=([%w_.-]+)")
    if not expires or not key_name then return false, "no Expires or KeyName" end
    if expires < now then return false, "expired" end

    local url = BASE_URL .. path .. "?" .. signed_part
    if verified[url .. "&Signature=" .. sig] == expires then return true end

    load_keys(now)
    local key = keys[key_name]
    if not key then return false, "unknown KeyName " .. key_name .. (keys_error and (" (" .. keys_error .. ")") or "") end

    local expected = b64url_encode(hmac_sha1(key, url)):gsub("=+$", "")
    local given = sig:gsub("=+$", "")
    if not equal_ct(expected, given) then return false, "bad signature" end
    remember(url .. "&Signature=" .. sig, expires)
    return true
end

local function request_parts(r)
    local raw = r.unparsed_uri
    if raw and raw ~= "" then
        local path, query = raw:match("^([^?]*)%??(.*)$")
        return path, query
    end
    return r.uri, r.args
end

local function check(r, enforce)
    local path, query = request_parts(r)
    local ok, reason = verify(path, query, os.time())
    if ok then
        r.notes["signed_url"] = "ok"
        return apache2.DECLINED           -- valid: let the rest of the access checks decide
    end
    r.notes["signed_url"] = "invalid"
    r:warn(("signed_urls: %s %s: %s"):format(enforce and "denied" or "would deny", path, reason))
    if enforce then return 403 end
    return apache2.DECLINED
end

-- Hook functions named in LuaHookAccessChecker
function check_signed_url(r) return check(r, true) end
function check_signed_url_log(r) return check(r, false) end

-- Internals, for selftest.lua
signed_urls = {
    sha1 = sha1, hmac_sha1 = hmac_sha1, b64url_encode = b64url_encode, b64url_decode = b64url_decode,
    verify = verify,
    set_keys = function(k) keys, keys_loaded_at, verified, verified_count = k, math.huge, {}, 0 end,
    BASE_URL = BASE_URL,
}
