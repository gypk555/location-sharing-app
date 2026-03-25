import React, {
  createContext,
  useContext,
  useState,
  useEffect,
  useCallback,
} from 'react';
import AsyncStorage from '@react-native-async-storage/async-storage';

const API_URL = 'http://10.0.2.2:3001';

export interface AuthUser {
  uid: string;
  phone?: string;
  email?: string;
  name?: string;
  photoUrl?: string;
  authProvider: 'phone' | 'email' | 'google' | 'apple';
}

interface AuthContextType {
  user: AuthUser | null;
  loading: boolean;
  error: string | null;

  // Phone OTP
  sendPhoneOtp: (phone: string) => Promise<string>;
  verifyPhoneOtp: (otp: string) => Promise<void>;

  // Email/Password
  registerWithEmail: (email: string, password: string, name: string) => Promise<void>;
  loginWithEmail: (email: string, password: string) => Promise<void>;

  // Social
  signInWithGoogle: () => Promise<void>;
  signInWithApple: () => Promise<void>;

  // Common
  signOut: () => Promise<void>;
  clearError: () => void;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

const USER_STORAGE_KEY = '@auth_user';

export function AuthProvider({children}: {children: React.ReactNode}) {
  const [user, setUser] = useState<AuthUser | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [pendingPhone, setPendingPhone] = useState<string | null>(null);

  // Load stored user on mount
  useEffect(() => {
    const loadStoredUser = async () => {
      try {
        const stored = await AsyncStorage.getItem(USER_STORAGE_KEY);
        if (stored) {
          setUser(JSON.parse(stored));
        }
      } catch (e) {
        console.error('Failed to load stored user:', e);
      } finally {
        setLoading(false);
      }
    };
    loadStoredUser();
  }, []);

  // Demo: Phone OTP (simulated)
  const sendPhoneOtp = useCallback(async (phone: string): Promise<string> => {
    setPendingPhone(phone);
    // In demo mode, any 6-digit code works
    return 'demo-verification-id';
  }, []);

  const verifyPhoneOtp = useCallback(
    async (otp: string): Promise<void> => {
      if (otp.length !== 6) {
        setError('OTP must be 6 digits');
        throw new Error('Invalid OTP');
      }

      const demoUser: AuthUser = {
        uid: 'demo-phone-' + Date.now(),
        phone: pendingPhone || '+1234567890',
        authProvider: 'phone',
      };
      await AsyncStorage.setItem(USER_STORAGE_KEY, JSON.stringify(demoUser));
      setUser(demoUser);
      setPendingPhone(null);
    },
    [pendingPhone],
  );

  // Demo: Email Registration
  const registerWithEmail = useCallback(
    async (email: string, password: string, name: string): Promise<void> => {
      if (!email || !password || !name) {
        setError('All fields are required');
        throw new Error('All fields are required');
      }

      const demoUser: AuthUser = {
        uid: 'demo-email-' + Date.now(),
        email,
        name,
        authProvider: 'email',
      };
      await AsyncStorage.setItem(USER_STORAGE_KEY, JSON.stringify(demoUser));
      setUser(demoUser);
    },
    [],
  );

  // Demo: Email Login
  const loginWithEmail = useCallback(
    async (email: string, password: string): Promise<void> => {
      if (!email || !password) {
        setError('Email and password are required');
        throw new Error('Email and password are required');
      }

      const demoUser: AuthUser = {
        uid: 'demo-email-' + Date.now(),
        email,
        name: email.split('@')[0],
        authProvider: 'email',
      };
      await AsyncStorage.setItem(USER_STORAGE_KEY, JSON.stringify(demoUser));
      setUser(demoUser);
    },
    [],
  );

  // Demo: Google Sign-In
  const signInWithGoogle = useCallback(async (): Promise<void> => {
    const demoUser: AuthUser = {
      uid: 'demo-google-' + Date.now(),
      email: 'demo@gmail.com',
      name: 'Demo User',
      authProvider: 'google',
    };
    await AsyncStorage.setItem(USER_STORAGE_KEY, JSON.stringify(demoUser));
    setUser(demoUser);
  }, []);

  // Demo: Apple Sign-In
  const signInWithApple = useCallback(async (): Promise<void> => {
    const demoUser: AuthUser = {
      uid: 'demo-apple-' + Date.now(),
      email: 'demo@icloud.com',
      name: 'Demo User',
      authProvider: 'apple',
    };
    await AsyncStorage.setItem(USER_STORAGE_KEY, JSON.stringify(demoUser));
    setUser(demoUser);
  }, []);

  // Sign Out
  const signOut = useCallback(async (): Promise<void> => {
    await AsyncStorage.removeItem(USER_STORAGE_KEY);
    setUser(null);
  }, []);

  const clearError = useCallback(() => {
    setError(null);
  }, []);

  return (
    <AuthContext.Provider
      value={{
        user,
        loading,
        error,
        sendPhoneOtp,
        verifyPhoneOtp,
        registerWithEmail,
        loginWithEmail,
        signInWithGoogle,
        signInWithApple,
        signOut,
        clearError,
      }}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  const context = useContext(AuthContext);
  if (!context) {
    throw new Error('useAuth must be used within an AuthProvider');
  }
  return context;
}
