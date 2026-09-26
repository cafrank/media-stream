import { useCallback, useEffect, useRef, useState } from 'react';

import { searchTracks, Track } from '@/services/catalogApi';

export interface TrackFilters {
    q: string;
    genre: string;
    version: string;
}

/** value, once it has stopped changing for delayMs */
function useDebouncedValue<T>(value: T, delayMs: number): T {
    const [debounced, setDebounced] = useState(value);
    useEffect(() => {
        const timer = setTimeout(() => setDebounced(value), delayMs);
        return () => clearTimeout(timer);
    }, [value, delayMs]);
    return debounced;
}

/**
 * The catalog, one server page at a time. Changing a filter (q is debounced 300 ms) starts again at page 0
 * and aborts the request in flight, so an older response never replaces a newer one. loadMore fetches the
 * next page; it does nothing while a page is loading or when every match is loaded. After a failed page,
 * calling loadMore again retries it.
 */
export function useTrackSearch(filters: TrackFilters, pageSize = 50) {
    const q = useDebouncedValue(filters.q.trim(), 300);
    const { genre, version } = filters;

    const [tracks, setTracks] = useState<Track[]>([]);
    const [total, setTotal] = useState(0);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState<string | null>(null);

    const controllerRef = useRef<AbortController | null>(null);
    const loadingRef = useRef(false); // set synchronously: onEndReached can fire twice before a re-render
    const nextPageRef = useRef(0);

    const load = useCallback(
        (page: number) => {
            controllerRef.current?.abort();
            const controller = new AbortController();
            controllerRef.current = controller;
            loadingRef.current = true;
            setLoading(true);
            setError(null);
            searchTracks({ q, genre, version, page, size: pageSize }, controller.signal)
                .then((result) => {
                    if (controller.signal.aborted) return;
                    setTracks((loaded) => (page === 0 ? result.tracks : [...loaded, ...result.tracks]));
                    setTotal(result.total);
                    nextPageRef.current = page + 1;
                })
                .catch((err) => {
                    if (!controller.signal.aborted) setError(err.message);
                })
                .finally(() => {
                    if (controllerRef.current !== controller) return;
                    loadingRef.current = false;
                    setLoading(false);
                });
        },
        [q, genre, version, pageSize]
    );

    // A filter changed (or first render): start again at page 0
    useEffect(() => {
        nextPageRef.current = 0;
        setTracks([]);
        setTotal(0);
        load(0);
        return () => controllerRef.current?.abort();
    }, [load]);

    const loadMore = useCallback(() => {
        if (loadingRef.current || nextPageRef.current === 0 || tracks.length >= total) return;
        load(nextPageRef.current);
    }, [load, tracks.length, total]);

    return { tracks, total, loading, error, loadMore };
}
