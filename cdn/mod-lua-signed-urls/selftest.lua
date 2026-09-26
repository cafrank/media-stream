-- selftest.lua: lua selftest.lua [path/to/signed_urls.lua]
-- Known-answer tests for SHA-1 (FIPS 180), HMAC-SHA1 (RFC 2202) and base64url, then verify() cases.
dofile(arg[1] or "signed_urls.lua")
local S = signed_urls
local failures = 0
local function hex(s) return (s:gsub(".", function(c) return ("%02x"):format(c:byte()) end)) end
local function eq(name, got, want)
    if got == want then print("  PASS  " .. name) else failures = failures + 1; print(("  FAIL  %s: got %s, want %s"):format(name, tostring(got), tostring(want))) end
end

eq("sha1('')", hex(S.sha1("")), "da39a3ee5e6b4b0d3255bfef95601890afd80709")
eq("sha1('abc')", hex(S.sha1("abc")), "a9993e364706816aba3e25717850c26c9cd0d89d")
eq("sha1(448-bit)", hex(S.sha1("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")), "84983e441c3bd26ebaae4aa1f95129e5e54670f1")
eq("sha1(a x 1000)", hex(S.sha1(string.rep("a", 1000))), "291e9a6c66994949b57ba5e650361e98fc36b1ba")
eq("hmac rfc2202 #1", hex(S.hmac_sha1(string.rep("\11", 20), "Hi There")), "b617318655057264e28bc0b6fb378c8ef146be00")
eq("hmac rfc2202 #2", hex(S.hmac_sha1("Jefe", "what do ya want for nothing?")), "effcdf6ae5eb2fa2d27416d5f184df9c259a7c79")
eq("hmac rfc2202 #6 (80-byte key)", hex(S.hmac_sha1(string.rep("\170", 80), "Test Using Larger Than Block-Size Key - Hash Key First")), "aa4ae5e15272d00e95705637ce8a3b55ed402112")
eq("b64url pad 1", S.b64url_encode("ab"), "YWI=")
eq("b64url pad 2", S.b64url_encode("a"), "YQ==")
eq("b64url alphabet", S.b64url_encode("\251\255\254"), "-__-")
eq("b64url round trip", S.b64url_decode("dvCuEDg4jJsTXIQgt6CkbA=="), S.b64url_decode(S.b64url_encode(S.b64url_decode("dvCuEDg4jJsTXIQgt6CkbA=="))))
eq("key decodes to 16 bytes", #S.b64url_decode("dvCuEDg4jJsTXIQgt6CkbA=="), 16)

-- verify(): sign like media-service (GcsSignUrl.signUrl)
local key = S.b64url_decode("dvCuEDg4jJsTXIQgt6CkbA==")
S.set_keys({ testkey = key })
local now = 1800000000
local function sign(path, prefix, expires, key_name)
    local q = (prefix and (prefix .. "&") or "") .. "Expires=" .. expires .. "&KeyName=" .. (key_name or "testkey")
    return q .. "&Signature=" .. S.b64url_encode(S.hmac_sha1(key, S.BASE_URL .. path .. "?" .. q))
end
local p = "/prev/gen3/402391.mp4"
local stream, dl = sign(p, nil, now + 60), sign(p, "download=1", now + 60)
eq("valid stream URL", S.verify(p, stream, now), true)
eq("valid download URL", S.verify(p, dl, now), true)
eq("valid again (cache hit)", S.verify(p, stream, now), true)
eq("cached signature on another path", S.verify("/prev/gen3/402392.mp4", stream, now), false)
eq("unsigned", S.verify(p, "", now), false)
eq("expired", S.verify(p, sign(p, nil, now - 1), now), false)
eq("download=1 removed", S.verify(p, (dl:gsub("^download=1&", "")), now), false)
eq("download=1 added", S.verify(p, "download=1&" .. stream, now), false)
eq("Expires changed", S.verify(p, (stream:gsub("Expires=%d+", "Expires=" .. (now + 999999))), now), false)
eq("unknown KeyName", S.verify(p, sign(p, nil, now + 60, "other"), now), false)
eq("parameter after Signature", S.verify(p, stream .. "&x=1", now), false)
eq("percent-encoded padding", S.verify(p, (stream:gsub("=$", "%%3D")), now), true)

-- Cost of one uncached verification
local n, t0 = 200, os.clock()
for i = 1, n do S.set_keys({ testkey = key }); S.verify(p, sign(p, nil, now + 60 + i), now) end
print(("  INFO  %.2f ms per sign+verify pair (2 HMACs, uncached), Lua %s"):format((os.clock() - t0) * 1000 / n, _VERSION))
print(failures == 0 and ">>> selftest: all passed" or (">>> selftest: " .. failures .. " FAILED"))
os.exit(failures == 0 and 0 or 1)
