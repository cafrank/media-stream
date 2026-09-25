import React, { useState, useEffect } from 'react';
import { ScrollView, View, Text, TextInput, TouchableOpacity, Image, StyleSheet } from 'react-native';
import { Play, Pause, DownloadCloud, Info, Search, Music } from 'react-native-vector-icons/dist/FontAwesome';
import { createBottomTabNavigator } from '@react-navigation/bottom-tabs'; // Changed to bottom tabs
import { NavigationContainer } from '@react-navigation/native';
// import { ScrollArea } from "@/components/ui/scroll-area" // Removed problematic import
import { AlertTriangle, X } from 'lucide-react'; // Added for error and alert icons

// --- Types ---
interface Track {
    id: string;
    title: string;
    artist: string;
    genre: string;
    version: string;
    audioUrl: string;
    artworkUrl: string;
    duration: string;
    fileFormat: 'mp3' | 'wav' | 'aiff';
    size: string;
}

// --- Components ---

const TrackListScreen = () => {
    const [tracks, setTracks] = useState<Track[]>([]);
    const [searchTerm, setSearchTerm] = useState<string>('');
    const [selectedGenre, setSelectedGenre] = useState<string>('');
    const [selectedVersion, setSelectedVersion] = useState<string>('');
    const [playingTrack, setPlayingTrack] = useState<string | null>(null);
    const [audio] = useState<HTMLAudioElement | null>(new Audio());
    const [downloadingTrackId, setDownloadingTrackId] = useState<string | null>(null);
    const [error, setError] = useState<string | null>(null);
    const [loading, setLoading] = useState<boolean>(false); // Add loading state

    // --- Fetch Tracks from API ---
    useEffect(() => {
        const fetchTracks = async () => {
            setLoading(true); // Set loading to true before fetching
            try {
                let url = `http://your-backend-api.com/api/search?searchTerm=${searchTerm}`;
                if (selectedGenre) {
                    url += `&genre=${selectedGenre}`;
                }
                if (selectedVersion) {
                    url += `&version=${selectedVersion}`;
                }

                const response = await fetch(url);
                if (!response.ok) {
                    throw new Error(`HTTP error! Status: ${response.status}`);
                }
                const data: Track[] = await response.json();
                setTracks(data);
            } catch (error: any) {
                setError(`Failed to fetch tracks: ${error.message}`);
            } finally {
                setLoading(false); // Set loading to false after fetching
            }
        };

        // Debounce function to delay API calls
        const debounce = (func: (...args: any[]) => void, delay: number) => {
            let timeoutId: NodeJS.Timeout;
            return (...args: any[]) => {
                if (timeoutId) {
                    clearTimeout(timeoutId);
                }
                timeoutId = setTimeout(() => {
                    func(...args);
                }, delay);
            };
        };

        // Use debounce to delay API calls by 300ms
        const debouncedFetch = debounce(fetchTracks, 300);

        debouncedFetch(); // Call debouncedFetch instead of fetchTracks

    }, [searchTerm, selectedGenre, selectedVersion]); // Dependency array

    // --- Audio Playback ---
      const togglePlay = (trackId: string) => {
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
            audio.src = trackToPlay.audioUrl;
             audio.play().then(() => {
                setPlayingTrack(trackId);
            }).catch((err: any) => { // Explicitly type err as any
                setError(`Error playing track: ${err.message}`);
                setPlayingTrack(null);
            });
        }
    };

    useEffect(() => {
        if (!audio) return;
        audio.addEventListener('ended', () => setPlayingTrack(null));
        audio.addEventListener('error', (e) => {
            setError(`Audio playback error: ${e.message}`);
            setPlayingTrack(null);
        });

        return () => {
            audio.removeEventListener('ended', () => setPlayingTrack(null));
            audio.removeEventListener('error', (e) => {
                setError(`Audio playback error: ${e.message}`);
                setPlayingTrack(null);
            });
        };
    }, [audio]);

    // --- Download ---
    const handleDownload = (trackId: string) => {
        setDownloadingTrackId(trackId);
        // Simulate download
        setTimeout(() => {
            setDownloadingTrackId(null);
            console.log(`Downloading track: ${trackId}`);
        }, 2000);
    };

    const showTrackInfo = (track: Track) => {
        navigation.navigate('TrackInfo', { track });
    };

    const clearError = () => {
        setError(null);
    };

    // Custom ScrollArea component for React Native, since the original import was for web.
    const ScrollAreaRN = ({ children, style }: { children: React.ReactNode, style?: any }) => (
        <ScrollView style={{ ...style }} contentContainerStyle={{ flexGrow: 1 }}>
            {children}
        </ScrollView>
    );

    return (
        <View style={styles.container}>
            <View style={styles.header}>
                <Text style={styles.headerTitle}>
                    <Music style={styles.headerIcon} size={30} color="#8b5cf6" />
                    Record Pool
                </Text>
                <Text style={styles.headerSubtitle}>
                    Your source for high-quality music
                </Text>
            </View>

            {/* Search and Filter */}
            <View style={styles.searchAndFilter}>
                <View style={styles.searchInputContainer}>
                    <TextInput
                        type="text"
                        placeholder="Search for tracks, artists..."
                        value={searchTerm}
                        onChangeText={(text) => setSearchTerm(text)}
                        style={styles.searchInput}
                    />
                    <Search style={styles.searchIcon} size={20} color="#9ca3af" />
                </View>

                <View style={styles.selectContainer}>
                    <select
                        value={selectedGenre}
                        onChange={(e) => setSelectedGenre(e.target.value)}
                        style={styles.select}
                    >
                        <option value="">All Genres</option>
                        {Array.from(new Set(tracks.map(track => track.genre))).map(genre => (
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
                        {Array.from(new Set(tracks.map(track => track.version))).map(version => (
                            <option key={version} value={version}>
                                {version}
                            </option>
                        ))}
                    </select>
                </View>
            </View>

            <ScrollAreaRN style={styles.trackList}>
                <View>
                    {loading ? ( // Show loading indicator
                        <View style={styles.loadingContainer}>
                            <Text style={styles.loadingText}>Loading Tracks...</Text>
                        </View>
                    ) : tracks.length === 0 ? (
                        <View style={styles.noTracksContainer}>
                            <Music size={40} color="#9ca3af" style={styles.noTracksIcon} />
                            <Text style={styles.noTracksTitle}>No Tracks Found</Text>
                            <Text style={styles.noTracksSubtitle}>Try adjusting your search or filters.</Text>
                        </View>
                    ) : (
                        tracks.map(track => (
                            <View key={track.id} style={styles.trackItem}>
                                <TouchableOpacity
                                    style={styles.trackInfoContainer}
                                    onPress={() => showTrackInfo(track)}
                                >
                                    <Image
                                        source={{ uri: track.artworkUrl }}
                                        style={styles.trackArtwork}
                                    />
                                    <View>
                                        <Text style={styles.trackTitle}>{track.title}</Text>
                                        <Text style={styles.trackDetails}>{track.artist} - {track.version}</Text>
                                    </View>
                                </TouchableOpacity>
                                <View style={styles.trackActions}>
                                    <TouchableOpacity
                                        onPress={() => togglePlay(track.id)}
                                        title={playingTrack === track.id ? 'Pause' : 'Play'}
                                    >
                                        {playingTrack === track.id ? (
                                            <Pause size={20} color="#fff" />
                                        ) : (
                                            <Play size={20} color="#fff" />
                                        )}
                                    </TouchableOpacity>
                                    <TouchableOpacity
                                        onPress={() => handleDownload(track.id)}
                                        disabled={!!downloadingTrackId && downloadingTrackId === track.id} //convert to boolean
                                        title="Download"
                                    >
                                        {downloadingTrackId === track.id ? (
                                            <svg className="animate-spin h-5 w-5 text-white" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                                                <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"></circle>
                                                <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                                            </svg>
                                        ) : (
                                            <DownloadCloud size={20} color="#fff" />
                                        )}
                                    </TouchableOpacity>
                                </View>
                            </View>
                        ))
                    )}
                </View>
            </ScrollAreaRN>
            {/* Error Message */}
            {error && (
                <View style={styles.errorContainer}>
                    <AlertTriangle size={20} color="#fff" />
                    <Text>{error}</Text>
                    <TouchableOpacity onPress={clearError}>
                        <X size={20} color="#fff" />
                    </TouchableOpacity>
                </View>
            )}
        </View>
    );
};

// Track Info Screen
const TrackInfoScreen = ({ route }: any) => { // Fix: Type the route parameter as any
    const { track } = route.params;

    return (
        <View style={styles.infoContainer}>
            <Text style={styles.infoTitle}>Track Information</Text>

            <Image
                source={{ uri: track.artworkUrl }}
                style={styles.infoArtwork}
            />

            <View style={styles.infoDetailsContainer}>
                <View style={styles.infoDetailRow}>
                    <Text style={styles.infoDetailLabel}>Title:</Text>
                    <Text style={styles.infoDetailValue}>{track.title}</Text>
                </View>
                <View style={styles.infoDetailRow}>
                    <Text style={styles.infoDetailLabel}>Artist:</Text>
                    <Text style={styles.infoDetailValue}>{track.artist}</Text>
                </View>
                <View style={styles.infoDetailRow}>
                    <Text style={styles.infoDetailLabel}>Genre:</Text>
                    <Text style={styles.infoDetailValue}>{track.genre}</Text>
                </View>
                <View style={styles.infoDetailRow}>
                    <Text style={styles.infoDetailLabel}>Version:</Text>
                    <Text style={styles.infoDetailValue}>{track.version}</Text>
                </View>
                <View style={styles.infoDetailRow}>
                    <Text style={styles.infoDetailLabel}>Duration:</Text>
                    <Text style={styles.infoDetailValue}>{track.duration}</Text>
                </View>
                <View style={styles.infoDetailRow}>
                    <Text style={styles.infoDetailLabel}>Format:</Text>
                    <Text style={styles.infoDetailValue}>{track.fileFormat.toUpperCase()}</Text>
                </View>
                <View style={styles.infoDetailRow}>
                    <Text style={styles.infoDetailLabel}>Size:</Text>
                    <Text style={styles.infoDetailValue}>{track.size}</Text>
                </View>
            </View>
        </View>
    );
};

const Tab = createBottomTabNavigator();

const App = () => {
    return (
        <NavigationContainer>
            <Tab.Navigator
                screenOptions={({ route }) => ({
                    tabBarIcon: ({ focused, color, size }) => {
                        let iconName;

                        if (route.name === 'Tracks') {
                            iconName = 'music';
                        } else if (route.name === 'Info') {
                            iconName = 'info';
                        }

                        // You can return any component that you like here!
                        return <FontAwesome name={iconName} size={size} color={color} />;
                    },
                    tabBarActiveTintColor: '#8b5cf6',
                    tabBarInactiveTintColor: 'gray',
                    tabBarStyle: {
                        backgroundColor: '#0f172a', // Dark background for tabs
                        borderTopColor: '#1d4ed8', // Darker border
                    },
                    tabBarLabelStyle: {
                        fontSize: 12,
                    }
                })}
            >
                <Tab.Screen name="Tracks" component={TrackListScreen} options={{ title: 'Tracks' }} />
                <Tab.Screen name="Info" component={TrackInfoScreen} options={{ title: 'Track Info' }} />
            </Tab.Navigator>
        </NavigationContainer>
    );
};

export default App;

const styles = StyleSheet.create({
    container: {
        flex: 1,
        backgroundColor: '#0f172a',
        padding: 10,
    },
    header: {
        marginBottom: 20,
    },
    headerTitle: {
        fontSize: 24,
        fontWeight: 'bold',
        color: '#8b5cf6',
        textAlign: 'center',
        display: 'flex',
        flexDirection: 'row',
        alignItems: 'center',
        justifyContent: 'center'
    },
    headerIcon: {
        marginRight: 10
    },
    headerSubtitle: {
        color: '#d1d5db',
        textAlign: 'center',
        fontSize: 16,
    },
    searchAndFilter: {
        flexDirection: 'column',
        gap: 10,
        marginBottom: 20,
    },
    searchInputContainer: {
        position: 'relative',
    },
    searchInput: {
        width: '100%',
        padding: 10,
        backgroundColor: 'rgba(0, 0, 0, 0.2)',
        color: '#fff',
        borderWidth: 1,
        borderColor: 'rgba(124, 58, 237, 0.3)',
        borderRadius: 5,
        paddingLeft: 35, // Make space for the icon
    },
    searchIcon: {
        position: 'absolute',
        left: 10,
        top: 10,
    },
    selectContainer: {
        flexDirection: 'row',
        gap: 10
    },
    select: {
        flex: 1,
        padding: 10,
        backgroundColor: 'rgba(0, 0, 0, 0.2)',
        color: '#fff',
        borderWidth: 1,
        borderColor: 'rgba(124, 58, 237, 0.3)',
        borderRadius: 5,
    },
    trackList: {
        flexGrow: 1,
    },
    loadingContainer: {
        backgroundColor: '#374151',
        padding: 20,
        borderRadius: 5,
        alignItems: 'center',
    },
    loadingText: {
        fontSize: 18,
        fontWeight: 'semibold',
        color: '#9ca3af',
        marginBottom: 5,
    },
    noTracksContainer: {
        backgroundColor: '#374151',
        padding: 20,
        borderRadius: 5,
        alignItems: 'center',
    },
    noTracksIcon: {
        marginBottom: 10
    },
    noTracksTitle: {
        fontSize: 18,
        fontWeight: 'semibold',
        color: '#9ca3af',
        marginBottom: 5,
    },
    noTracksSubtitle: {
        fontSize: 14,
        color: '#9ca3af',
    },
    trackItem: {
        flexDirection: 'row',
        justifyContent: 'space-between',
        alignItems: 'center',
        padding: 15,
        borderRadius: 5,
        backgroundColor: 'rgba(0, 0, 0, 0.2)',
        borderWidth: 1,
        borderColor: 'rgba(124, 58, 237, 0.2)',
        marginBottom: 10,
    },
    trackInfoContainer: {
        flexDirection: 'row',
        alignItems: 'center',
        gap: 15,
        flex: 1,
        marginRight: 10
    },
    trackArtwork: {
        width: 50,
        height: 50,
        borderRadius: 5,
    },
    trackTitle: {
        fontSize: 16,
        fontWeight: 'semibold',
        color: '#fff',
    },
    trackDetails: {
        fontSize: 12,
        color: '#d1d5db',
    },
    trackActions: {
        flexDirection: 'row',
        gap: 10,
    },
    errorContainer: {
        position: 'absolute',
        top: 20,
        left: '50%',
        transform: 'translateX(-50%)',
        backgroundColor: 'rgba(220, 38, 38, 0.9)',
        color: '#fff',
        paddingHorizontal: 20,
        paddingVertical: 10,
        borderRadius: 5,
        shadowColor: '#000',
        shadowOffset: { width: 0, height: 2 },
        shadowOpacity: 0.25,
        shadowRadius: 3.84,
        elevation: 5,
        display: 'flex',
        flexDirection: 'row',
        alignItems: 'center',
        gap: 10
    },
    infoContainer: {
        flex: 1,
        backgroundColor: '#0f172a',
        padding: 20,
        alignItems: 'center',
    },
    infoTitle: {
        fontSize: 24,
        fontWeight: 'bold',
        color: '#fff',
        marginBottom: 20,
    },
    infoArtwork: {
        width: 200,
        height: 200,
        borderRadius: 10,
        marginBottom: 20,
    },
    infoDetailsContainer: {
        gap: 10,
        width: '100%',
    },
    infoDetailRow: {
        flexDirection: 'row',
        justifyContent: 'space-between',
    },
    infoDetailLabel: {
        fontSize: 18,
        fontWeight: 'semibold',
        color: '#fff',
    },
    infoDetailValue: {
        fontSize: 18,
        color: '#d1d5db',
    },
});

