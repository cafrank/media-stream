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
 * next page; it does nothing while a page is loading, after a page failed, or when every match is loaded.
 * retry fetches the page that failed. Tracks already loaded are not added twice when the catalog changed
 * between pages (skip/limit paging shifts by the number of inserted tracks).
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
    // A failed page is retried only by retry(): the list's onEndReached would not fire again by itself
    const failedRef = useRef(false);

    const load = useCallback(
        (page: number) => {
            controllerRef.current?.abort();
            const controller = new AbortController();
            controllerRef.current = controller;
            loadingRef.current = true;
            failedRef.current = false;
            setLoading(true);
            setError(null);
            searchTracks({ q, genre, version, page, size: pageSize }, controller.signal)
                .then((result) => {
                    if (controller.signal.aborted) return;
                    setTracks((loaded) => {
                        if (page === 0) return result.tracks;
                        const seen = new Set(loaded.map((t) => t.id));
                        return [...loaded, ...result.tracks.filter((t) => !seen.has(t.id))];
                    });
                    setTotal(result.total);
                    nextPageRef.current = page + 1;
                })
                .catch((err) => {
                    if (controller.signal.aborted) return;
                    failedRef.current = true;
                    setError(err.message);
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
        if (loadingRef.current || failedRef.current || nextPageRef.current === 0 || tracks.length >= total) return;
        load(nextPageRef.current);
    }, [load, tracks.length, total]);

    /** Fetch the page that failed again (page 0 when the first page failed) */
    const retry = useCallback(() => {
        if (!loadingRef.current) load(nextPageRef.current);
    }, [load]);

    return { tracks, total, loading, error, loadMore, retry };
}
