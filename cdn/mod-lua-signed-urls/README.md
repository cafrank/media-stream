# Signed URLs on www.my12inch.com with mod_lua (#17)

**Status: installed on www.my12inch.com, enforcing since 2026-09-25.** It uses key `mykey3`; the old `mykey2`, whose value was in git, is revoked. media-service signs with the key from the Secret `media-service-signing`. Operations (key rotation, troubleshooting) are in `docs/borg-cloud-runbook.md`, "RecordPool downloads and signed URLs". The steps below are how it was installed, and how to reinstall it.

## What it is

An Apache `mod_lua` access checker that enforces the signed URLs media-service already hands out for
`/prev/gen3/<song_id>.<mp4|mp3>`:

```
https://www.my12inch.com/prev/gen3/402391.mp4?[download=1&]Expires=<unix s>&KeyName=<name>&Signature=<b64url HMAC-SHA1>
```

- **Same format as today:** it is the Cloud CDN format from `GcsSignUrl`, so media-service doesn't change.
- **What the signature covers:** everything before `&Signature=`, including `https://www.my12inch.com` and `download=1`. `Signature` must be the last parameter.
- **Lua:**
  - Pure Lua 5.1, because CentOS 7's Lua has no bit library.
  - HMAC-SHA1 costs about 0.9 ms. A verified URL is then cached in each httpd child until it expires, so the range requests a video player makes don't pay for the HMAC again.
- **Two modes:**
  - `check_signed_url_log` serves everything and logs `signed_urls: would deny <path>: <reason>` to `error_log`.
  - `check_signed_url` returns 403.
- **Directory listing:** the config also turns it off for `/prev` (`Options -Indexes`). Today `/prev/gen3/` lists the whole catalog.

| File | Goes to | |
|---|---|---|
| `signed_urls.lua` | `/etc/httpd/signed-urls/signed_urls.lua` | the hook |
| `signed-urls.conf` | `/etc/httpd/conf.d/signed-urls.conf` | Apache config, log-only as shipped |
| `keys.example` | `/etc/httpd/signed-urls/keys` | `<KeyName> <base64url key>` per line, reread every 60 s |
| `selftest.lua` | not installed | known-answer tests (FIPS 180 SHA-1, RFC 2202 HMAC) and verify() cases |
| `test/` | not installed | the server's httpd build in Docker, tested end to end |

## Evaluate it locally

```bash
cdn/mod-lua-signed-urls/test/run-tests.sh
```

- **Build:** a `centos:7` container (vault repos) with the same `httpd-2.4.6-97.el7.centos`, prefork MPM and Lua 5.1.4 as the server.
- **Tests:**
  - the Lua self-test
  - log-only mode
  - enforce mode, and key rotation
  - a URL signed by the live media-service (skipped if `MEDIA_API` isn't reachable)
  - latency
- **Result on 2026-09-26:** all checks pass.

| Measured (container, concurrency 8, `Range: bytes=0-0`) | Mean per request |
|---|---|
| Same file without the hook | 0.433 ms |
| With the hook, cached URL | 0.421 ms (no measurable cost) |
| With the hook, a new URL every request | ~0.9 ms of HMAC (self-test). The script's 5 ms figure is mostly `curl` process startup. |

## Install on www.my12inch.com

The server runs CentOS 7.9 with `httpd-2.4.6-97.el7.centos`, prefork. `lua_module`, `headers_module` and `setenvif_module` are already loaded. Nothing needs to be installed from packages.

**Order matters:**
1. Install in log-only mode.
2. Change media-service's key and expiry.
3. Enforce.

Enforcing with today's key achieves nothing: `mykey2` and its value are in git. Enforcing with today's 50 s expiry breaks playback, because a video player keeps making range requests long after the URL was issued.

### 1. Back up the config and copy the files

```bash
ssh root@169.45.92.99 'cp -a /etc/httpd /root/httpd-backup-$(date +%F)'
scp cdn/mod-lua-signed-urls/{signed_urls.lua,signed-urls.conf} root@169.45.92.99:/tmp/
```

### 2. Install in log-only mode

On the server:

```bash
install -d -o root -g apache -m 0750 /etc/httpd/signed-urls
# keys must be a file: an empty directory named keys makes every URL fail with "unknown KeyName" 
install -o root -g root -m 0644 /tmp/signed_urls.lua /etc/httpd/signed-urls/signed_urls.lua
# The key media-service signs with, from its Secret. Run the kubectl on the host and pipe it in, so the key
# never lands in a file or the shell history:
#   kubectl -n media get secret media-service-signing -o jsonpath='{.data.SIGNING_KEY_NAME}{" "}{.data.SIGNING_KEY}' \
#     | awk '{ "echo " $1 " | base64 -d" | getline n; "echo " $2 " | base64 -d" | getline k; print n, k }' \
#     | ssh root@169.45.92.99 'cat > /etc/httpd/signed-urls/keys'
chown root:apache /etc/httpd/signed-urls/keys && chmod 0640 /etc/httpd/signed-urls/keys
install -o root -g root -m 0644 /tmp/signed-urls.conf /etc/httpd/conf.d/signed-urls.conf
apachectl -t && systemctl reload httpd       # reload is graceful; running downloads continue
```

### 3. Check it

From anywhere:

```bash
curl -sI https://www.my12inch.com/prev/gen3/402391.mp4 | head -1             # 200 (log-only), logged as "would deny"
curl -s -o /dev/null -w '%{http_code}\n' https://www.my12inch.com/prev/gen3/  # 403: no more directory listing
URL=$(curl -s http://192.168.56.120/api/media/6ab70696a67f2f6a670ad9bf/stream)
curl -s -o /dev/null -r 0-99 -w '%{http_code}\n' "$URL"                        # 206, and nothing logged for it
```

On the server:

```bash
grep -h 'signed_urls:' /var/log/httpd/ssl_error_log /var/log/httpd/error_log | tail   # HTTPS requests log to ssl_error_log
```

### 4. Watch the log-only mode (a day or more)

Every request the enforce mode would refuse is logged. The client's address is on each line:

```bash
grep -h 'signed_urls: would deny' /var/log/httpd/ssl_error_log /var/log/httpd/error_log \
  | sed -E 's/.*\[client ([0-9.]+):[0-9]+\].*: ([^:]+)$/\1 \2/' | sort | uniq -c | sort -rn | head -20
```

Anything besides RecordPool through media-service that still fetches `/prev/gen3/` shows up here as `unsigned`. That includes the DJ apps, the old site, and anything using the listing. Decide on each of these before enforcing.

### 5. Rotate the key and fix the expiry (media-service changes)

- **New key:** generate one, and put it in the keys file next to the old one:

  ```bash
  NEW=$(head -c 16 /dev/urandom | base64 | tr '+/' '-_')
  printf 'mykey3 %s\n' "$NEW" >> /etc/httpd/signed-urls/keys    # both keys are valid now; picked up within 60 s
  ```

- **media-service:** it reads the key from the Secret `media-service-signing` (`SIGNING_KEY_NAME`, `SIGNING_KEY`) through `CdnSigner`. `/stream` URLs last the track length plus 2 h (4 h when the length is unknown), and `/download` URLs 10 min. Update the Secret with the new key, then run `kubectl -n media rollout restart deploy/media-service`.
- **Retire the old key:** once the new URLs are out and the old ones have expired, remove the `mykey2` line.

### 6. Enforce

In `/etc/httpd/conf.d/signed-urls.conf`, comment out the `check_signed_url_log` line and uncomment the `check_signed_url` line. Then:

```bash
apachectl -t && systemctl reload httpd
curl -sI https://www.my12inch.com/prev/gen3/402391.mp4 | head -1     # 403
```

### Rollback

Put the `check_signed_url_log` line back, or remove `/etc/httpd/conf.d/signed-urls.conf`, then run `apachectl -t && systemctl reload httpd`.

## Notes and limits

- **Clock:** it compares `Expires` with `os.time()`, which is UTC seconds. The server's time zone (America/Chicago) doesn't matter, but its clock must be NTP-synced.
- **Cache:** one per httpd child (prefork), capped at 20,000 URLs and then cleared. Each child verifies a URL once. `LuaCodeCache stat` reloads the script when the file changes.
- **Keys file:** readable by the `apache` user, so anything else running as `apache` on this box (CGI, the JSP app's proxy targets) could read it. Keep the file mode at 0640 root:apache, and keep keys out of `conf.d/`, where `*.conf` would be read as Apache config.
- **Scope:** only `/prev/gen3/` is checked. `/xyz/` (`/home2/void/flv`) is still listable and unsigned. That is out of scope here and should be handled separately.
- **`download=1` header:** `SetEnvIfExpr` sets `Content-Disposition: attachment` on the response. Plain `SetEnvIf Query_String ...` doesn't work, because SetEnvIf has no query-string attribute.
- **Long term:** CentOS 7 and httpd 2.4.6 are end of life. Moving the files to object storage with native signed URLs is the longer-term plan (#17 discussion).
