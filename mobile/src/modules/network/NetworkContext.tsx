import React, {
  createContext,
  useContext,
  useState,
  useEffect,
  useCallback,
  useRef,
} from 'react';
import NetInfo, {NetInfoState} from '@react-native-community/netinfo';

export interface NetworkStatus {
  isConnected: boolean;
  type: 'wifi' | 'cellular' | 'none' | 'unknown';
  isInternetReachable: boolean | null;
  offlineSince: Date | null;
  offlineDurationMs: number;
}

interface NetworkContextType {
  status: NetworkStatus;
  isOnline: boolean;
  checkConnectivity: () => Promise<boolean>;
  onFallbackTrigger: (callback: (status: NetworkStatus) => void) => () => void;
}

const NetworkContext = createContext<NetworkContextType | undefined>(undefined);

// Configuration
const FALLBACK_DELAY_MS = 30000; // 30 seconds before triggering SMS fallback
const CONNECTIVITY_CHECK_INTERVAL = 10000; // 10 seconds

export function NetworkProvider({children}: {children: React.ReactNode}) {
  const [status, setStatus] = useState<NetworkStatus>({
    isConnected: true,
    type: 'unknown',
    isInternetReachable: null,
    offlineSince: null,
    offlineDurationMs: 0,
  });

  const offlineTimestampRef = useRef<Date | null>(null);
  const fallbackTriggeredRef = useRef(false);
  const fallbackCallbacksRef = useRef<Set<(status: NetworkStatus) => void>>(
    new Set(),
  );
  const checkIntervalRef = useRef<NodeJS.Timeout | null>(null);

  // Map connection type
  const mapConnectionType = useCallback(
    (type: string): 'wifi' | 'cellular' | 'none' | 'unknown' => {
      switch (type) {
        case 'wifi':
          return 'wifi';
        case 'cellular':
          return 'cellular';
        case 'none':
          return 'none';
        default:
          return 'unknown';
      }
    },
    [],
  );

  // Check actual connectivity with a network request
  const checkConnectivity = useCallback(async (): Promise<boolean> => {
    try {
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), 5000);

      await fetch('https://clients3.google.com/generate_204', {
        method: 'HEAD',
        signal: controller.signal,
      });

      clearTimeout(timeout);
      return true;
    } catch {
      return false;
    }
  }, []);

  // Check if fallback should be triggered
  const checkFallbackTrigger = useCallback(() => {
    const offlineTimestamp = offlineTimestampRef.current;
    if (!offlineTimestamp) return;

    const offlineDuration = Date.now() - offlineTimestamp.getTime();

    if (
      offlineDuration >= FALLBACK_DELAY_MS &&
      !fallbackTriggeredRef.current
    ) {
      fallbackTriggeredRef.current = true;

      const currentStatus: NetworkStatus = {
        isConnected: false,
        type: 'none',
        isInternetReachable: false,
        offlineSince: offlineTimestamp,
        offlineDurationMs: offlineDuration,
      };

      // Notify all registered callbacks
      fallbackCallbacksRef.current.forEach(callback => {
        try {
          callback(currentStatus);
        } catch (e) {
          console.error('Fallback callback error:', e);
        }
      });
    }
  }, []);

  // Handle network state changes
  const handleNetworkChange = useCallback(
    async (state: NetInfoState) => {
      const wasConnected = status.isConnected;
      let isNowConnected =
        state.isConnected && state.isInternetReachable !== false;

      // Double-check with actual request if NetInfo says we're connected
      if (isNowConnected) {
        isNowConnected = await checkConnectivity();
      }

      if (wasConnected && !isNowConnected) {
        // Just went offline
        offlineTimestampRef.current = new Date();
        fallbackTriggeredRef.current = false;

        // Schedule fallback check
        setTimeout(checkFallbackTrigger, FALLBACK_DELAY_MS);
      } else if (!wasConnected && isNowConnected) {
        // Back online
        offlineTimestampRef.current = null;
        fallbackTriggeredRef.current = false;
      }

      setStatus({
        isConnected: isNowConnected,
        type: mapConnectionType(state.type),
        isInternetReachable: isNowConnected,
        offlineSince: offlineTimestampRef.current,
        offlineDurationMs: offlineTimestampRef.current
          ? Date.now() - offlineTimestampRef.current.getTime()
          : 0,
      });
    },
    [status.isConnected, checkConnectivity, checkFallbackTrigger, mapConnectionType],
  );

  // Subscribe to network changes
  useEffect(() => {
    const unsubscribe = NetInfo.addEventListener(handleNetworkChange);

    // Initial fetch
    NetInfo.fetch().then(handleNetworkChange);

    // Periodic connectivity check
    checkIntervalRef.current = setInterval(async () => {
      const state = await NetInfo.fetch();
      handleNetworkChange(state);
    }, CONNECTIVITY_CHECK_INTERVAL);

    return () => {
      unsubscribe();
      if (checkIntervalRef.current) {
        clearInterval(checkIntervalRef.current);
      }
    };
  }, [handleNetworkChange]);

  // Register fallback callback
  const onFallbackTrigger = useCallback(
    (callback: (status: NetworkStatus) => void) => {
      fallbackCallbacksRef.current.add(callback);
      return () => {
        fallbackCallbacksRef.current.delete(callback);
      };
    },
    [],
  );

  return (
    <NetworkContext.Provider
      value={{
        status,
        isOnline: status.isConnected,
        checkConnectivity,
        onFallbackTrigger,
      }}>
      {children}
    </NetworkContext.Provider>
  );
}

export function useNetwork() {
  const context = useContext(NetworkContext);
  if (!context) {
    throw new Error('useNetwork must be used within a NetworkProvider');
  }
  return context;
}
