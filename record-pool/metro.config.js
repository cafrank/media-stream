// Metro config: Expo's defaults, plus a dev-server proxy for the API.
//
// The app calls the API on its own origin (EXPO_PUBLIC_API_URL empty, see constants/Api.ts). Behind the
// BorgCloud ingress /api/media is media-service. On `expo start` the dev server would answer /api/* with
// Expo Router's 404 page, so the dev server forwards /api/* to RECORD_POOL_DEV_API (default: the BorgCloud
// VIP). Same origin, so no CORS, from localhost:3000 and from the LAN alike. Only the dev server uses this;
// `expo export` builds are unaffected.
const http = require('http');
const https = require('https');
const { getDefaultConfig } = require('expo/metro-config');

const config = getDefaultConfig(__dirname);
const target = new URL(process.env.RECORD_POOL_DEV_API || 'http://192.168.56.120');

function proxyApi(req, res) {
    const url = new URL(req.url, target);
    const client = url.protocol === 'https:' ? https : http;
    const upstream = client.request(
        url,
        { method: req.method, headers: { ...req.headers, host: url.host } },
        (answer) => {
            res.writeHead(answer.statusCode, answer.headers);
            answer.pipe(res);
        }
    );
    upstream.on('error', (err) => {
        res.writeHead(502, { 'Content-Type': 'text/plain' });
        res.end(`RecordPool dev proxy: ${target.origin} unreachable (${err.message})`);
    });
    req.pipe(upstream);
}

const expoEnhance = config.server?.enhanceMiddleware;   // Expo's own, if any: keep it in the chain
config.server = {
    ...config.server,
    enhanceMiddleware: (middleware, server) => {
        const metro = expoEnhance ? expoEnhance(middleware, server) : middleware;
        return (req, res, next) => (req.url.startsWith('/api/') ? proxyApi(req, res) : metro(req, res, next));
    },
};

module.exports = config;
