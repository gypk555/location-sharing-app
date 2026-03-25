import React, {
  createContext,
  useContext,
  useState,
  useEffect,
  useCallback,
  useRef,
} from 'react';
import {Platform, PermissionsAndroid, Alert} from 'react-native';
import Geolocation from 'react-native-geolocation-service';

export interface LocationData {
  latitude: number;
  longitude: number;
  accuracy: number;
  altitude?: number;
  altitudeAccuracy?: number;
  heading?: number;
  speed?: number;
  timestamp: Date;
}

interface LocationContextType {
  currentLocation: LocationData | null;
  isTracking: boolean;
  isLoading: boolean;
  error: string | null;

  requestPermission: () => Promise<boolean>;
  startTracking: () => Promise<void>;
  stopTracking: () => void;
  getCurrentPosition: () => Promise<LocationData>;

  // Listeners
  onLocationUpdate: (callback: (location: LocationData) => void) => () => void;
}

const LocationContext = createContext<LocationContextType | undefined>(undefined);

export function LocationProvider({children}: {children: React.ReactNode}) {
  const [currentLocation, setCurrentLocation] = useState<LocationData | null>(null);
  const [isTracking, setIsTracking] = useState(false);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const watchIdRef = useRef<number | null>(null);
  const locationCallbacksRef = useRef<Set<(location: LocationData) => void>>(
    new Set(),
  );

  // Request location permission
  const requestPermission = useCallback(async (): Promise<boolean> => {
    try {
      if (Platform.OS === 'android') {
        const fineLocation = await PermissionsAndroid.request(
          PermissionsAndroid.PERMISSIONS.ACCESS_FINE_LOCATION,
          {
            title: 'Location Permission',
            message:
              'This app needs access to your location to share it with your friends.',
            buttonNeutral: 'Ask Me Later',
            buttonNegative: 'Cancel',
            buttonPositive: 'OK',
          },
        );

        if (fineLocation !== PermissionsAndroid.RESULTS.GRANTED) {
          setError('Location permission denied');
          return false;
        }

        // Request background location for Android 10+
        if (Platform.Version >= 29) {
          const backgroundLocation = await PermissionsAndroid.request(
            PermissionsAndroid.PERMISSIONS.ACCESS_BACKGROUND_LOCATION,
            {
              title: 'Background Location Permission',
              message:
                'This app needs background location access to share your location even when the app is in the background.',
              buttonNeutral: 'Ask Me Later',
              buttonNegative: 'Cancel',
              buttonPositive: 'OK',
            },
          );

          if (backgroundLocation !== PermissionsAndroid.RESULTS.GRANTED) {
            Alert.alert(
              'Limited Functionality',
              'Background location was not granted. Location sharing will only work when the app is open.',
            );
          }
        }

        return true;
      }

      // iOS permission is handled by the Geolocation API automatically
      return true;
    } catch (e: any) {
      setError(e.message || 'Failed to request permission');
      return false;
    }
  }, []);

  // Convert Geolocation position to LocationData
  const positionToLocationData = useCallback(
    (position: GeolocationPosition): LocationData => ({
      latitude: position.coords.latitude,
      longitude: position.coords.longitude,
      accuracy: position.coords.accuracy,
      altitude: position.coords.altitude ?? undefined,
      altitudeAccuracy: position.coords.altitudeAccuracy ?? undefined,
      heading: position.coords.heading ?? undefined,
      speed: position.coords.speed ?? undefined,
      timestamp: new Date(position.timestamp),
    }),
    [],
  );

  // Get current position once
  const getCurrentPosition = useCallback(async (): Promise<LocationData> => {
    return new Promise((resolve, reject) => {
      setIsLoading(true);
      setError(null);

      Geolocation.getCurrentPosition(
        position => {
          const locationData = positionToLocationData(position);
          setCurrentLocation(locationData);
          setIsLoading(false);
          resolve(locationData);
        },
        err => {
          setError(err.message);
          setIsLoading(false);
          reject(err);
        },
        {
          enableHighAccuracy: true,
          timeout: 30000,
          maximumAge: 5000,
        },
      );
    });
  }, [positionToLocationData]);

  // Start continuous tracking
  const startTracking = useCallback(async (): Promise<void> => {
    if (isTracking) return;

    const hasPermission = await requestPermission();
    if (!hasPermission) {
      throw new Error('Location permission not granted');
    }

    setIsTracking(true);
    setError(null);

    watchIdRef.current = Geolocation.watchPosition(
      position => {
        const locationData = positionToLocationData(position);
        setCurrentLocation(locationData);

        // Notify all registered callbacks
        locationCallbacksRef.current.forEach(callback => {
          try {
            callback(locationData);
          } catch (e) {
            console.error('Location callback error:', e);
          }
        });
      },
      err => {
        setError(err.message);
      },
      {
        enableHighAccuracy: true,
        distanceFilter: 10, // Update every 10 meters
        interval: 5000, // Android: minimum interval between updates
        fastestInterval: 3000, // Android: fastest interval
      },
    );
  }, [isTracking, requestPermission, positionToLocationData]);

  // Stop tracking
  const stopTracking = useCallback(() => {
    if (watchIdRef.current !== null) {
      Geolocation.clearWatch(watchIdRef.current);
      watchIdRef.current = null;
    }
    setIsTracking(false);
  }, []);

  // Register location update callback
  const onLocationUpdate = useCallback(
    (callback: (location: LocationData) => void) => {
      locationCallbacksRef.current.add(callback);
      return () => {
        locationCallbacksRef.current.delete(callback);
      };
    },
    [],
  );

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      if (watchIdRef.current !== null) {
        Geolocation.clearWatch(watchIdRef.current);
      }
    };
  }, []);

  return (
    <LocationContext.Provider
      value={{
        currentLocation,
        isTracking,
        isLoading,
        error,
        requestPermission,
        startTracking,
        stopTracking,
        getCurrentPosition,
        onLocationUpdate,
      }}>
      {children}
    </LocationContext.Provider>
  );
}

export function useLocation() {
  const context = useContext(LocationContext);
  if (!context) {
    throw new Error('useLocation must be used within a LocationProvider');
  }
  return context;
}
