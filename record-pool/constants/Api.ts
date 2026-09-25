/**
 * Base URL of the MediaStream API, inlined at build time from EXPO_PUBLIC_API_URL.
 * Empty (the default) means the same origin as the web app, e.g. behind the
 * BorgCloud ingress where /api/media routes to media-service.
 */
export const API_URL = (process.env.EXPO_PUBLIC_API_URL ?? '').replace(/\/+$/, '');
