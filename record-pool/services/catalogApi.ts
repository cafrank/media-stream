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

async function get(path: string, signal?: AbortSignal): Promise<Response> {
    const response = await fetch(`${API_URL}${path}`, { signal });
    if (!response.ok) {
        throw new Error(`GET ${path}: HTTP ${response.status}`);
    }
    return response;
}

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

/** Every track in the catalog. media-service has no search or paging yet, so callers filter locally. */
export async function fetchTracks(signal?: AbortSignal): Promise<Track[]> {
    const response = await get('/api/media', signal);
    const body: MediaResponse[] = await response.json();
    return body.map(toTrack);
}

/** A short-lived signed URL to play the track (GET /api/media/{id}/stream returns it as text). */
export async function fetchStreamUrl(id: string): Promise<string> {
    const response = await get(`/api/media/${encodeURIComponent(id)}/stream`);
    return (await response.text()).trim();
}
