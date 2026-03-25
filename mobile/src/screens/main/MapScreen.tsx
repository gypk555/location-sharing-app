import React, {useEffect, useState, useCallback, useRef} from 'react';
import {
  View,
  Text,
  TouchableOpacity,
  StyleSheet,
  ActivityIndicator,
  Alert,
  Platform,
} from 'react-native';
import {useNavigation} from '@react-navigation/native';
import {NativeStackNavigationProp} from '@react-navigation/native-stack';
import MapView, {Marker, PROVIDER_GOOGLE} from 'react-native-maps';
import {MainStackParamList} from '../../navigation/MainNavigator';
import {useLocation, LocationData} from '../../modules/location/LocationContext';
import {useNetwork} from '../../modules/network/NetworkContext';
import {
  shareLocationViaSms,
  defaultSmsOptions,
} from '../../modules/sms/smsService';

type MapScreenNavProp = NativeStackNavigationProp<MainStackParamList, 'MainTabs'>;

export default function MapScreen() {
  const navigation = useNavigation<MapScreenNavProp>();
  const mapRef = useRef<MapView>(null);
  const {
    currentLocation,
    isTracking,
    isLoading,
    error,
    startTracking,
    stopTracking,
    getCurrentPosition,
  } = useLocation();
  const {status: networkStatus, isOnline} = useNetwork();

  const [sharingEnabled, setSharingEnabled] = useState(false);

  // Center map on current location
  useEffect(() => {
    if (currentLocation && mapRef.current) {
      mapRef.current.animateToRegion({
        latitude: currentLocation.latitude,
        longitude: currentLocation.longitude,
        latitudeDelta: 0.01,
        longitudeDelta: 0.01,
      });
    }
  }, [currentLocation]);

  // Start tracking when sharing is enabled
  useEffect(() => {
    if (sharingEnabled && !isTracking) {
      startTracking().catch(e => {
        Alert.alert('Error', e.message || 'Failed to start location tracking');
        setSharingEnabled(false);
      });
    } else if (!sharingEnabled && isTracking) {
      stopTracking();
    }
  }, [sharingEnabled, isTracking, startTracking, stopTracking]);

  // Toggle location sharing
  const handleToggleSharing = useCallback(() => {
    setSharingEnabled(!sharingEnabled);
  }, [sharingEnabled]);

  // Share location via SMS manually
  const handleShareViaSms = useCallback(async () => {
    let location = currentLocation;

    if (!location) {
      try {
        location = await getCurrentPosition();
      } catch (e: any) {
        Alert.alert('Error', e.message || 'Could not get location');
        return;
      }
    }

    // For demo, use empty recipients - in real app, show contact picker
    Alert.alert(
      'Share Location',
      'This will open your SMS app with your location ready to send.',
      [
        {text: 'Cancel', style: 'cancel'},
        {
          text: 'Share',
          onPress: async () => {
            try {
              const result = await shareLocationViaSms(
                location!,
                [], // Empty array will just open SMS compose with message
                defaultSmsOptions,
                'manual',
              );
              if (!result.success) {
                Alert.alert('Error', result.error || 'Failed to share');
              }
            } catch (e: any) {
              Alert.alert('Error', e.message || 'Failed to share location');
            }
          },
        },
      ],
    );
  }, [currentLocation, getCurrentPosition]);

  // Navigate to SOS
  const handleSos = useCallback(() => {
    navigation.navigate('Sos');
  }, [navigation]);

  // Format coordinates for display
  const formatCoordinate = (value: number, isLat: boolean) => {
    const direction = isLat
      ? value >= 0
        ? 'N'
        : 'S'
      : value >= 0
        ? 'E'
        : 'W';
    return `${Math.abs(value).toFixed(6)}° ${direction}`;
  };

  return (
    <View style={styles.container}>
      {/* Network Status Banner */}
      {!isOnline && (
        <View style={styles.offlineBanner}>
          <Text style={styles.offlineBannerText}>
            Offline - SMS fallback active
          </Text>
        </View>
      )}

      {/* Map View */}
      <View style={styles.mapContainer}>
        <MapView
          ref={mapRef}
          style={styles.map}
          provider={Platform.OS === 'android' ? PROVIDER_GOOGLE : undefined}
          showsUserLocation
          showsMyLocationButton
          initialRegion={{
            latitude: currentLocation?.latitude || 37.78825,
            longitude: currentLocation?.longitude || -122.4324,
            latitudeDelta: 0.01,
            longitudeDelta: 0.01,
          }}>
          {currentLocation && (
            <Marker
              coordinate={{
                latitude: currentLocation.latitude,
                longitude: currentLocation.longitude,
              }}
              title="My Location"
              description={`Accuracy: ±${Math.round(currentLocation.accuracy)}m`}
            />
          )}
        </MapView>

        {/* Current Location Overlay */}
        {currentLocation && (
          <View style={styles.locationOverlay}>
            <Text style={styles.locationTitle}>Your Location</Text>
            <Text style={styles.locationCoord}>
              {formatCoordinate(currentLocation.latitude, true)}
            </Text>
            <Text style={styles.locationCoord}>
              {formatCoordinate(currentLocation.longitude, false)}
            </Text>
            <Text style={styles.locationAccuracy}>
              ±{Math.round(currentLocation.accuracy)}m accuracy
            </Text>
          </View>
        )}
      </View>

      {/* Controls */}
      <View style={styles.controls}>
        {/* Sharing Toggle */}
        <TouchableOpacity
          style={[
            styles.sharingButton,
            sharingEnabled && styles.sharingButtonActive,
          ]}
          onPress={handleToggleSharing}
          disabled={isLoading}>
          {isLoading ? (
            <ActivityIndicator color={sharingEnabled ? '#FFFFFF' : '#007AFF'} />
          ) : (
            <>
              <Text
                style={[
                  styles.sharingButtonIcon,
                  sharingEnabled && styles.sharingButtonIconActive,
                ]}>
                {sharingEnabled ? '📍' : '📍'}
              </Text>
              <Text
                style={[
                  styles.sharingButtonText,
                  sharingEnabled && styles.sharingButtonTextActive,
                ]}>
                {sharingEnabled ? 'Sharing Location' : 'Start Sharing'}
              </Text>
            </>
          )}
        </TouchableOpacity>

        {/* Action Buttons */}
        <View style={styles.actionButtons}>
          {/* Share via SMS */}
          <TouchableOpacity
            style={styles.actionButton}
            onPress={handleShareViaSms}>
            <Text style={styles.actionButtonIcon}>💬</Text>
            <Text style={styles.actionButtonText}>Share via SMS</Text>
          </TouchableOpacity>

          {/* SOS Button */}
          <TouchableOpacity
            style={[styles.actionButton, styles.sosButton]}
            onPress={handleSos}>
            <Text style={styles.actionButtonIcon}>🆘</Text>
            <Text style={[styles.actionButtonText, styles.sosButtonText]}>
              SOS
            </Text>
          </TouchableOpacity>
        </View>

        {/* Status Info */}
        <View style={styles.statusInfo}>
          <View style={styles.statusItem}>
            <View
              style={[
                styles.statusDot,
                isOnline ? styles.statusDotOnline : styles.statusDotOffline,
              ]}
            />
            <Text style={styles.statusText}>
              {isOnline ? 'Online' : 'Offline'}
            </Text>
          </View>
          <View style={styles.statusItem}>
            <View
              style={[
                styles.statusDot,
                isTracking ? styles.statusDotOnline : styles.statusDotOffline,
              ]}
            />
            <Text style={styles.statusText}>
              {isTracking ? 'Tracking' : 'Not tracking'}
            </Text>
          </View>
        </View>

        {/* Error Display */}
        {error && (
          <View style={styles.errorContainer}>
            <Text style={styles.errorText}>{error}</Text>
          </View>
        )}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#FFFFFF',
  },
  offlineBanner: {
    backgroundColor: '#FF9500',
    paddingVertical: 8,
    paddingHorizontal: 16,
    alignItems: 'center',
  },
  offlineBannerText: {
    color: '#FFFFFF',
    fontWeight: '600',
    fontSize: 14,
  },
  mapContainer: {
    flex: 1,
    position: 'relative',
  },
  map: {
    flex: 1,
  },
  locationOverlay: {
    position: 'absolute',
    top: 16,
    left: 16,
    backgroundColor: 'rgba(255, 255, 255, 0.95)',
    padding: 16,
    borderRadius: 12,
    shadowColor: '#000',
    shadowOffset: {width: 0, height: 2},
    shadowOpacity: 0.1,
    shadowRadius: 4,
    elevation: 3,
  },
  locationTitle: {
    fontSize: 14,
    fontWeight: '600',
    color: '#333333',
    marginBottom: 8,
  },
  locationCoord: {
    fontSize: 13,
    color: '#666666',
    fontFamily: Platform.OS === 'ios' ? 'Menlo' : 'monospace',
  },
  locationAccuracy: {
    fontSize: 12,
    color: '#8E8E93',
    marginTop: 8,
  },
  controls: {
    padding: 16,
    backgroundColor: '#FFFFFF',
    borderTopWidth: 1,
    borderTopColor: '#E5E5EA',
  },
  sharingButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: '#F2F2F7',
    borderRadius: 12,
    paddingVertical: 16,
    marginBottom: 16,
    borderWidth: 2,
    borderColor: 'transparent',
  },
  sharingButtonActive: {
    backgroundColor: '#007AFF',
    borderColor: '#007AFF',
  },
  sharingButtonIcon: {
    fontSize: 20,
    marginRight: 8,
  },
  sharingButtonIconActive: {},
  sharingButtonText: {
    fontSize: 16,
    fontWeight: '600',
    color: '#007AFF',
  },
  sharingButtonTextActive: {
    color: '#FFFFFF',
  },
  actionButtons: {
    flexDirection: 'row',
    gap: 12,
    marginBottom: 16,
  },
  actionButton: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: '#F2F2F7',
    borderRadius: 12,
    paddingVertical: 14,
  },
  sosButton: {
    backgroundColor: '#FF3B30',
  },
  actionButtonIcon: {
    fontSize: 18,
    marginRight: 8,
  },
  actionButtonText: {
    fontSize: 14,
    fontWeight: '600',
    color: '#333333',
  },
  sosButtonText: {
    color: '#FFFFFF',
  },
  statusInfo: {
    flexDirection: 'row',
    justifyContent: 'center',
    gap: 24,
  },
  statusItem: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  statusDot: {
    width: 8,
    height: 8,
    borderRadius: 4,
    marginRight: 6,
  },
  statusDotOnline: {
    backgroundColor: '#34C759',
  },
  statusDotOffline: {
    backgroundColor: '#FF3B30',
  },
  statusText: {
    fontSize: 13,
    color: '#8E8E93',
  },
  errorContainer: {
    marginTop: 12,
    padding: 12,
    backgroundColor: '#FFE5E5',
    borderRadius: 8,
  },
  errorText: {
    color: '#FF3B30',
    fontSize: 14,
    textAlign: 'center',
  },
});
