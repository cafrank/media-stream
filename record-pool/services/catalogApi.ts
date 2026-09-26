import { API_URL } from '@/constants/Api';

/** A track as the app shows it. */
export interface Track {
    id: string;
    title: string;
    artist: string;
    genre: string;
    /** media-service `remix`: "Original Mix", "Dub Mix", "Clean Edit", ... Empty when unknown */
    version: string;
    artworkUrl: string;
    bpm: number | null;
    year: number | null;
    /** "m:ss", or empty when media-service has no length */
    duration: string;
    /** Not in the catalog yet */
    fileFormat: 'mp3' | 'wav' | 'aiff' | null;
    /** Not in the catalog yet */
    size: string | null;
}

/** media-service `MediaResponse` (GET /api/media). Every field can be null. */
interface MediaResponse {
    id: string;
    song_id: number | null;
    title: string | null;
    artist: string | null;
    genre: string | null;
    remix: string | null;
    bpm: number | null;
    year: number | null;
    length: number | null;
    cover_url: string | null;
}

async function request(method: 'GET' | 'POST', path: string, signal?: AbortSignal): Promise<Response> {
    const response = await fetch(`${API_URL}${path}`, { method, signal });
    if (!response.ok) {
        throw new Error(`${method} ${path}: HTTP ${response.status}`);
    }
    return response;
}

const get = (path: string, signal?: AbortSignal) => request('GET', path, signal);

function formatDuration(seconds: number | null): string {
    if (seconds == null || seconds < 0) return '';
    const s = Math.round(seconds);
    return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
}

export function toTrack(m: MediaResponse): Track {
    return {
        id: m.id,
        title: m.title ?? '',
        artist: m.artist ?? '',
        genre: m.genre ?? '',
        version: m.remix ?? '',
        artworkUrl: m.cover_url ?? '',
        bpm: m.bpm,
        year: m.year,
        duration: formatDuration(m.length),
        fileFormat: null,
        size: null,
    };
}

/** Search filters and the page to fetch. Empty q, genre or version means no filter. page counts from 0. */
export interface TrackQuery {
    q?: string;
    genre?: string;
    version?: string;
    page: number;
    size: number;
}

/** One page of results. total counts every match. */
export interface TrackPage {
    tracks: Track[];
    page: number;
    size: number;
    total: number;
}

/** The values for the genre and version dropdowns */
export interface Facets {
    genres: string[];
    versions: string[];
}

/** One page of the catalog, newest first (GET /api/media/search) */
export async function searchTracks(query: TrackQuery, signal?: AbortSignal): Promise<TrackPage> {
    const params = new URLSearchParams({ page: String(query.page), size: String(query.size) });
    if (query.q) params.set('q', query.q);
    if (query.genre) params.set('genre', query.genre);
    if (query.version) params.set('version', query.version);
    const response = await get(`/api/media/search?${params}`, signal);
    const body: { items: MediaResponse[]; page: number; size: number; total: number } = await response.json();
    return { tracks: body.items.map(toTrack), page: body.page, size: body.size, total: body.total };
}

/** Distinct genres and versions in the catalog (GET /api/media/facets) */
export async function fetchFacets(signal?: AbortSignal): Promise<Facets> {
    const response = await get('/api/media/facets', signal);
    return response.json();
}

/** A short-lived signed URL to play the track (GET /api/media/{id}/stream returns it as text). */
export async function fetchStreamUrl(id: string): Promise<string> {
    const response = await get(`/api/media/${encodeURIComponent(id)}/stream`);
    return (await response.text()).trim();
}

/** media-service `SignedUrlResponse` (POST /api/media/{id}/download) */
export interface SignedUrl {
    url: string;
    /** ISO-8601 */
    expiresAt: string;
}

/** A short-lived signed URL that downloads the track's file (the CDN answers with Content-Disposition: attachment). */
export async function fetchDownloadUrl(id: string): Promise<SignedUrl> {
    const response = await request('POST', `/api/media/${encodeURIComponent(id)}/download`);
    return response.json();
}
