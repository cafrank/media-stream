import React, { useState, useEffect, useCallback } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import {
    Music,
    DownloadCloud,
    Play,
    Pause,
    AlertTriangle,
    X,
    Info,
    Search
} from 'lucide-react';
import { ScrollView, View, Text, TextInput, TouchableOpacity, StyleSheet, Image, Platform } from 'react-native';

import { fetchStreamUrl, fetchTracks, Track } from '@/services/catalogApi';


// Animation Variants
const trackItemVariants = {
    hidden: { opacity: 0, translateY: -10 },
    visible: { opacity: 1, translateY: 0, transition: { duration: 0.3 } },
    exit: { opacity: 0, translateY: 10, transition: { duration: 0.2 } },
};

const ScrollArea = ({ children, style }: { children: React.ReactNode, style?: any }) => {
  return (
    <ScrollView style={{...style}}>
      {children}
    </ScrollView>
  )
}

const RecordPoolApp = () => {
    const [tracks, setTracks] = useState<Track[]>([]);
    const [loading, setLoading] = useState(true);
    const [searchTerm, setSearchTerm] = useState('');
    const [selectedGenre, setSelectedGenre] = useState('');
    const [selectedVersion, setSelectedVersion] = useState('');
    const [playingTrack, setPlayingTrack] = useState<string | null>(null);
    const [audio] = useState<HTMLAudioElement | null>(new Audio());
    const [downloadingTrackId, setDownloadingTrackId] = useState<string | null>(null);
    const [error, setError] = useState<string | null>(null);
    const [trackInfo, setTrackInfo] = useState<Track | null>(null);
    const [isInfoModalOpen, setIsInfoModalOpen] = useState(false);

    // --- Catalog (media-service GET /api/media) ---
    useEffect(() => {
        const controller = new AbortController();
        fetchTracks(controller.signal)
            .then(setTracks)
            .catch((err) => {
                if (!controller.signal.aborted) setError(`Failed to load tracks: ${err.message}`);
            })
            .finally(() => {
                if (!controller.signal.aborted) setLoading(false);
            });
        return () => controller.abort();
    }, []);

    const availableGenres = Array.from(new Set(tracks.map((t) => t.genre).filter(Boolean))).sort();
    const availableVersions = Array.from(new Set(tracks.map((t) => t.version).filter(Boolean))).sort();


    // --- Search & Filter ---
    const filteredTracks = tracks.filter((track) => {
        const searchMatch =
            track.title.toLowerCase().includes(searchTerm.toLowerCase()) ||
            track.artist.toLowerCase().includes(searchTerm.toLowerCase());
        const genreMatch = !selectedGenre || track.genre === selectedGenre;
        const versionMatch = !selectedVersion || track.version === selectedVersion;
        return searchMatch && genreMatch && versionMatch;
    });

    // --- Audio Playback ---
    const togglePlay = useCallback(
        (trackId: string) => {
            if (!audio) return;

            const trackToPlay = tracks.find((track) => track.id === trackId);
            if (!trackToPlay) return;

            if (playingTrack === trackId) {
                audio.pause();
                setPlayingTrack(null);
            } else {
                if (playingTrack) {
                    audio.pause();
                }
                fetchStreamUrl(trackId).then((url) => {
                    audio.src = url;
                    return audio.play();
                }).then(() => {
                    setPlayingTrack(trackId);
                }).catch(err => {
                    setError(`Error playing track: ${err.message}`);
                    setPlayingTrack(null);
                });
            }
        },
        [audio, playingTrack, tracks]
    );

    useEffect(() => {
        if (!audio) return;
        const onEnded = () => setPlayingTrack(null);
        const onError = () => {
            setError(`Audio playback error: ${audio.error?.message || 'the track could not be played'}`);
            setPlayingTrack(null);
        };
        audio.addEventListener('ended', onEnded);
        audio.addEventListener('error', onError);

        return () => {
            audio.removeEventListener('ended', onEnded);
            audio.removeEventListener('error', onError);
        };
    }, [audio]);

    // --- Download ---
    const handleDownload = (trackId: string) => {
        setDownloadingTrackId(trackId);
        // Simulate download with a delay
        setTimeout(() => {
            setDownloadingTrackId(null);
            // In a real app, you would trigger a download here, e.g.,:
            // window.location.href = `/api/download?trackId=${trackId}`;
            console.log(`Downloading track: ${trackId}`);
        }, 2000); // Simulate a 2-second download
    };

    const showTrackInfo = (track: Track) => {
        setTrackInfo(track);
        setIsInfoModalOpen(true);
    };

    const clearError = () => {
        setError(null);
    };

    return (
        <View style={styles.container}>
            <View style={styles.header}>
                <Text style={styles.title}>
                    <Music style={styles.titleIcon} />
                    Record Pool
                </Text>
                <Text style={styles.subtitle}>
                    Your source for high-quality music
                </Text>
            </View>

            {/* Search and Filter */}
            <View style={styles.searchAndFilter}>
                <View style={styles.searchInputContainer}>
                    <TextInput
                        style={styles.searchInput}
                        placeholder="Search for tracks, artists..."
                        value={searchTerm}
                        onChangeText={(text) => setSearchTerm(text)}
                    />
                    <Search style={styles.searchIcon} />
                </View>

                <select
                    value={selectedGenre}
                    onChange={(e) => setSelectedGenre(e.target.value)}
                    style={styles.select}
                >
                    <option value="">All Genres</option>
                    {availableGenres.map((genre) => (
                        <option key={genre} value={genre}>
                            {genre}
                        </option>
                    ))}
                </select>

                <select
                    value={selectedVersion}
                    onChange={(e) => setSelectedVersion(e.target.value)}
                    style={styles.select}
                >
                    <option value="">All Versions</option>
                    {availableVersions.map((version) => (
                        <option key={version} value={version}>
                            {version}
                        </option>
                    ))}
                </select>
            </View>

            {/* Track List */}
            <ScrollArea style={styles.trackListContainer}>
                <View style={styles.trackList}>
                    <AnimatePresence>
                        {loading ? (
                            <View style={styles.noTracks}>
                                <Text style={styles.noTracksTitle}>Loading tracks...</Text>
                            </View>
                        ) : filteredTracks.length === 0 ? (
                            <View style={styles.noTracks}>
                                <Music style={styles.noTracksIcon} />
                                <Text style={styles.noTracksTitle}>No Tracks Found</Text>
                                <Text style={styles.noTracksText}>Try adjusting your search or filters.</Text>
                            </View>
                        ) : (
                            filteredTracks.map((track) => (
                                <motion.div
                                    key={track.id}
                                    variants={trackItemVariants}
                                    initial="hidden"
                                    animate="visible"
                                    exit="exit"
                                    style={styles.trackItem}
                                >
                                    <TouchableOpacity
                                        style={styles.trackInfoContainer}
                                        onPress={() => showTrackInfo(track)}
                                    >
                                        <Image
                                            source={track.artworkUrl ? { uri: track.artworkUrl } : undefined}
                                            style={styles.trackArtwork}
                                        />
                                        <View style={styles.trackTextContainer}>
                                            <Text style={styles.trackTitle}>{track.title}</Text>
                                            <Text style={styles.trackDetails}>
                                                {[track.artist, track.version].filter(Boolean).join(' - ')}
                                            </Text>
                                        </View>
                                    </TouchableOpacity>
                                    <View style={styles.trackActions}>
                                        <TouchableOpacity
                                            onPress={() => togglePlay(track.id)}
                                            style={styles.actionButton}
                                            title={playingTrack === track.id ? 'Pause' : 'Play'}
                                        >
                                            {playingTrack === track.id ? (
                                                <Pause style={styles.actionIcon} />
                                            ) : (
                                                <Play style={styles.actionIcon} />
                                            )}
                                        </TouchableOpacity>
                                        <TouchableOpacity
                                            onPress={() => handleDownload(track.id)}
                                            style={styles.actionButton}
                                            disabled={downloadingTrackId === track.id}
                                            title="Download"
                                        >
                                            {downloadingTrackId === track.id ? (
                                                <View style={styles.downloadingIcon}>
                                                    <Text>...</Text>
                                                </View>
                                            ) : (
                                                <DownloadCloud style={styles.actionIcon} />
                                            )}
                                        </TouchableOpacity>
                                    </View>
                                </motion.div>
                            ))
                        )}
                    </AnimatePresence>
                </View>
            </ScrollArea>

            {/* Track Info Modal */}
            <AnimatePresence>
                {isInfoModalOpen && trackInfo && (
                    <motion.div
                        initial={{ opacity: 0, scale: 0.8 }}
                        animate={{ opacity: 1, scale: 1 }}
                        exit={{ opacity: 0, scale: 0.8 }}
                        transition={{ duration: 0.2 }}
                        style={styles.modalOverlay}
                    >
                        <View style={styles.modalContent}>
                            <View style={styles.modalHeader}>
                                <Text style={styles.modalTitle}>Track Information</Text>
                                <TouchableOpacity
                                    onPress={() => setIsInfoModalOpen(false)}
                                    style={styles.modalCloseButton}
                                >
                                    <X style={styles.modalCloseIcon} />
                                </TouchableOpacity>
                            </View>
                            <View style={styles.modalBody}>
                                <View style={styles.modalTrackInfo}>
                                    <Image
                                        source={trackInfo.artworkUrl ? { uri: trackInfo.artworkUrl } : undefined}
                                        style={styles.modalArtwork}
                                    />
                                    <View style={styles.modalTrackTextContainer}>
                                        <Text style={styles.modalTrackTitle}>{trackInfo.title}</Text>
                                        <Text style={styles.modalTrackDetails}>
                                            Artist: {trackInfo.artist}
                                        </Text>
                                        <Text style={styles.modalTrackDetails}>
                                            Genre: {trackInfo.genre || '—'}
                                        </Text>
                                        <Text style={styles.modalTrackDetails}>
                                            Version: {trackInfo.version || '—'}
                                        </Text>
                                        <Text style={styles.modalTrackDetails}>
                                            BPM: {trackInfo.bpm ?? '—'} · Year: {trackInfo.year ?? '—'}
                                        </Text>
                                    </View>
                                </View>
                                <View style={styles.modalDetailsContainer}>
                                    <Text style={styles.modalDetailsTitle}>
                                        Additional Details
                                    </Text>
                                    <Text style={styles.modalDetailsText}>
                                        Duration: {trackInfo.duration || '—'}
                                    </Text>
                                    <Text style={styles.modalDetailsText}>
                                        File Format: {trackInfo.fileFormat?.toUpperCase() ?? '—'}
                                    </Text>
                                    <Text style={styles.modalDetailsText}>
                                        Size: {trackInfo.size ?? '—'}
                                    </Text>
                                </View>
                            </View>
                        </View>
                    </motion.div>
                )}
            </AnimatePresence>

            {/* Error Message */}
            <AnimatePresence>
                {error && (
                    <motion.div
                        initial={{ opacity: 0, translateY: -20 }}
                        animate={{ opacity: 1, translateY: 0 }}
                        exit={{ opacity: 0, translateY: -20 }}
                        style={styles.errorContainer}
                    >
                        <AlertTriangle style={styles.errorIcon} />
                        <Text style={styles.errorText}>{error}</Text>
                        <TouchableOpacity
                            onPress={clearError}
                            style={styles.errorCloseButton}
                        >
                            <X style={styles.errorCloseIcon} />
                        </TouchableOpacity>
                    </motion.div>
                )}
            </AnimatePresence>
        </View>
    );
};

const styles = StyleSheet.create({
    container: {
        flex: 1,
        backgroundColor: '#0f172a', // Dark background
        padding: 20,
    },
    header: {
        alignItems: 'center',
        marginBottom: 20,
    },
    title: {
        fontSize: 32,
        fontWeight: 'bold',
        color: '#6366f1', // Vibrant purple
        marginBottom: 8,
        display: 'flex',
        flexDirection: 'row',
        alignItems: 'center',
    },
    titleIcon: {
        marginRight: 8,
        width: 32,
        height: 32,
        color: '#6366f1',
    },
    subtitle: {
        fontSize: 16,
        color: '#d1d5db', // Grayish text
    },
    searchAndFilter: {
        flexDirection: 'column',
        gap: 16,
        marginBottom: 20,
    },
    searchInputContainer: {
        flexDirection: 'row',
        alignItems: 'center',
        backgroundColor: 'rgba(0, 0, 0, 0.2)',
        borderRadius: 8,
        paddingHorizontal: 10,
        borderColor: '#8b5cf6',
        borderWidth: 1,
    },
    searchInput: {
        flex: 1,
        color: '#fff',
        paddingVertical: 12,
        paddingHorizontal: 8,
        fontSize: 16,
    },
    searchIcon: {
        color: '#d1d5db',
        width: 20,
        height: 20,
    },
    select: {
        backgroundColor: 'rgba(0, 0, 0, 0.2)',
        color: '#fff',
        paddingVertical: 12,
        paddingHorizontal: 16,
        borderRadius: 8,
        fontSize: 16,
        borderColor: '#8b5cf6',
        borderWidth: 1,
    },
    trackListContainer: {
        flex: 1,
        borderRadius: 8,
        overflow: 'hidden',
    },
    trackList: {
        padding: 10,
    },
    trackItem: {
        flexDirection: 'row',
        alignItems: 'center',
        justifyContent: 'space-between',
        backgroundColor: 'rgba(0, 0, 0, 0.2)',
        borderRadius: 8,
        padding: 16,
        marginBottom: 12,
        borderColor: '#8b5cf6',
        borderWidth: 1,
    },
    trackInfoContainer: {
        flexDirection: 'row',
        alignItems: 'center',
        gap: 16,
        flex: 1,
    },
    trackArtwork: {
        width: 50,
        height: 50,
        borderRadius: 8,
        overflow: 'hidden',
    },
    trackTextContainer: {
        flex: 1,
    },
    trackTitle: {
        fontSize: 18,
        fontWeight: 'semibold',
        color: '#fff',
    },
    trackDetails: {
        fontSize: 14,
        color: '#d1d5db',
    },
    trackActions: {
        flexDirection: 'row',
        gap: 12,
    },
    actionButton: {
        backgroundColor: 'rgba(107, 114, 128, 0.2)', // Gray button
        padding: 10,
        borderRadius: 24,
    },
    actionIcon: {
        width: 20,
        height: 20,
        color: '#fff',
    },
    downloadingIcon: {
        width: 20,
        height: 20,
        borderRadius: 10,
        backgroundColor: 'rgba(255,255,255,1)',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center'
    },
    modalOverlay: {
        position: 'absolute',
        top: 0,
        left: 0,
        right: 0,
        bottom: 0,
        backgroundColor: 'rgba(0, 0, 0, 0.5)',
        justifyContent: 'center',
        alignItems: 'center',
        zIndex: 10,
    },
    modalContent: {
        backgroundColor: '#1f2937', // Darker modal background
        borderRadius: 12,
        width: '90%',
        maxWidth: 500,
        padding: 20,
        borderColor: '#8b5cf6',
        borderWidth: 1,
    },
    modalHeader: {
        flexDirection: 'row',
        justifyContent: 'space-between',
        alignItems: 'center',
        marginBottom: 16,
    },
    modalTitle: {
        fontSize: 24,
        fontWeight: 'bold',
        color: '#fff',
    },
    modalCloseButton: {
        padding: 8,
    },
    modalCloseIcon: {
        width: 24,
        height: 24,
        color: '#d1d5db',
    },
    modalBody: {
        space: 16
    },
    modalTrackInfo: {
        flexDirection: 'row',
        alignItems: 'center',
        gap: 16,
    },
    modalArtwork: {
        width: 80,
        height: 80,
        borderRadius: 8,
        overflow: 'hidden',
    },
    modalTrackTextContainer: {
        flex: 1,
    },
    modalTrackTitle: {
        fontSize: 20,
        fontWeight: 'semibold',
        color: '#fff',
    },
    modalTrackDetails: {
        fontSize: 14,
        color: '#d1d5db',
    },
    modalDetailsContainer: {

    },
    modalDetailsTitle: {
        fontSize: 16,
        fontWeight: 'semibold',
        color: '#fff',
        marginBottom: 8,
    },
    modalDetailsText: {
        fontSize: 14,
        color: '#d1d5db',
    },
    errorContainer: {
        position: 'absolute',
        top: 40,
        left: 0,
        right: 0,
        backgroundColor: 'rgba(220, 38, 38, 0.9)', // Darker red
        padding: 16,
        borderRadius: 8,
        marginHorizontal: 20,
        zIndex: 100,
        flexDirection: 'row',
        alignItems: 'center',
        gap: 12,
    },
    errorIcon: {
        width: 24,
        height: 24,
        color: '#fff',
    },
    errorText: {
        flex: 1,
        color: '#fff',
        fontSize: 16,
    },
    errorCloseButton: {
        padding: 8,
    },
    errorCloseIcon: {
        width: 20,
        height: 20,
        color: '#fff',
    },
    noTracks: {
        alignItems: 'center',
        justifyContent: 'center',
        paddingVertical: 40,
    },
    noTracksIcon: {
        width: 40,
        height: 40,
        color: '#d1d5db',
        marginBottom: 16,
    },
    noTracksTitle: {
        fontSize: 20,
        fontWeight: 'semibold',
        color: '#d1d5db',
        marginBottom: 8,
    },
    noTracksText: {
        fontSize: 14,
        color: '#d1d5db',
    }
});

export default RecordPoolApp;
